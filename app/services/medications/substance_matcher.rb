module Medications
  # Casa o princípio ativo publicado pela Anvisa/CMED com a base de substâncias
  # controladas (`Substance`), que é quem decide o tipo SNCR da receita.
  #
  # O casamento é **exato sobre formas normalizadas**, nunca aproximado: o texto
  # da Anvisa vem com sal, éster e grau de hidratação ("cloridrato de tramadol",
  # "amoxicilina tri-hidratada", "ceftriaxona dissódica hemieptaidratada"),
  # enquanto o Anexo I da 344/98 nomeia a substância-base. Este matcher desfaz só
  # essas variações de forma farmacêutica do mesmo princípio — o que sobra fica
  # sem vínculo e vai para o relatório de revisão da importação, porque adivinhar
  # por semelhança classificaria receita controlada errado (ver
  # docs/sncr/SUBSTANCES_DATA_SOURCING.md §7 e §8).
  class SubstanceMatcher
    # Sais e ésteres que aparecem como prefixo: "<sal> de <substância>".
    SALT_PREFIXES = %w[
      cloridrato dicloridrato hidrocloreto bromidrato hidrobrometo sulfato bissulfato
      acetato maleato besilato mesilato dimesilato tosilato napsilato fumarato hemifumarato
      tartarato bitartarato hemitartarato hidrogenotartarato succinato citrato nitrato fosfato difosfato
      pamoato embonato valerato propionato dipropionato butirato palmitato enantato decanoato
      caproato isocaproato fempropionato cipionato undecilato undecanoato oxalato malato
      lactato gluconato carbonato bicarbonato cloreto brometo iodeto estearato estolato
      xinafoato furoato salicilato aspartato orotato glicolato benzoato trometamol
    ].freeze

    # Adjetivo do contraíon que o prefixo pode carregar junto: "succinato sódico de X".
    COUNTER_ION_ADJECTIVES = %w[sodico dissodico potassico calcico magnesico zincico].freeze

    SALT_PREFIX = /\A(?:#{SALT_PREFIXES.join('|')})(?:\s+(?:#{COUNTER_ION_ADJECTIVES.join('|')}))?\s+de\s+/

    # "valproato de sódio" (CMED) e "valproato sódico" (Anexo I) são a mesma coisa.
    COUNTER_ION_PHRASES = {
      /\s+de\s+sodio\z/ => " sodico",
      /\s+de\s+potassio\z/ => " potassico",
      /\s+de\s+calcio\z/ => " calcico",
      /\s+de\s+magnesio\z/ => " magnesico",
      /\s+de\s+zinco\z/ => " zincico"
    }.freeze

    # Grau de hidratação: "tri-hidratada", "pentaidratado", "hemieptaidratada".
    HYDRATION = /\s+(?:(?:mono|di|tri|tetra|penta|hexa|hepta|epta|hemi|semi)\s*)*(?:hidratad|idratad)[oa]s?\z/

    # Sufixos que indicam sal/éster do mesmo princípio ativo.
    SALT_SUFFIXES = %w[
      sodico sodica dissodico dissodica potassico potassica calcico calcica magnesico
      magnesica zincico zincica benzatina trometamol axetil proxetil pivoxila medoxomila
      medocarila mofetila dipivoxila anidro anidra micronizado micronizada tamponado
      tamponada base
    ].freeze

    SALT_SUFFIX = /\s+(?:#{SALT_SUFFIXES.join('|')})\z/

    # Separadores de associação no campo SUBSTÂNCIA da CMED (o ";" é o usado hoje).
    INGREDIENT_SEPARATOR = /[;+]/

    def initialize(substances: Substance.ordered)
      @index = build_index(substances)
    end

    # Quebra o campo de princípio ativo em tokens (associações vêm num campo só).
    def self.split_ingredients(field)
      field.to_s.gsub(/\([^)]*\)/, " ").split(INGREDIENT_SEPARATOR).map { |token| token.squish }.reject(&:empty?)
    end

    # Substância correspondente ao princípio ativo, ou nil quando não há
    # casamento seguro.
    def match(ingredient)
      candidates(ingredient).each do |candidate|
        substance = @index[candidate]
        return substance if substance
      end

      nil
    end

    # Nome de substância "parecido" com um princípio ativo que não casou. Não
    # gera vínculo: só alimenta o relatório de curadoria da importação.
    def near_miss(ingredient)
      value = normalize(ingredient)
      return nil if value.length < 6

      @index.keys.find do |key|
        key.length >= 6 && (value.include?(key) || key.include?(value))
      end
    end

    # Formas normalizadas testadas, da mais literal para a mais reduzida.
    def candidates(ingredient)
      forms = []
      value = normalize(ingredient)
      forms << value

      COUNTER_ION_PHRASES.each { |phrase, adjective| value = value.sub(phrase, adjective) }
      forms << value

      value = value.sub(SALT_PREFIX, "")
      forms << value

      value = value.sub(HYDRATION, "")
      forms << value

      value = value.sub(SALT_SUFFIX, "") while value.match?(SALT_SUFFIX)
      forms << value

      forms.flat_map { |form| [ form, form.delete(" "), dcb_variant(form), gender_variant(form) ] }.compact_blank.uniq
    end

    private

    # Minúsculas, sem acento e sem pontuação — o mesmo tratamento dos dois lados
    # do casamento, para que "N-etilanfetamina" e "n etilanfetamina" convirjam.
    def normalize(value)
      value.to_s
           .unicode_normalize(:nfd)
           .gsub(/\p{Mn}/, "")
           .downcase
           .gsub(/[^a-z0-9]+/, " ")
           .squish
    end

    # A DCB alterna o final "-ila"/"-il" ("cefadroxila" na CMED, "cefadroxil" na
    # 344/98). Só corta o "a" final quando o que sobra termina em "il"/"ol".
    def dcb_variant(value)
      candidate = value.sub(/a\z/, "")
      candidate if candidate != value && candidate.match?(/(?:il|ol)\z/)
    end

    # A CMED e o Anexo I divergem no gênero do mesmo princípio ativo
    # ("ciprofloxacino" na lista de preços, "ciprofloxacina" na IN 360/2025).
    # Só troca a vogal final de "-ino"/"-ina": não existe par de substâncias
    # distintas que difira apenas nisso.
    def gender_variant(value)
      case value
      when /ino\z/ then value.sub(/ino\z/, "ina")
      when /ina\z/ then value.sub(/ina\z/, "ino")
      end
    end

    # Índice nome normalizado -> substância. Registra também os sinônimos que a
    # curadoria guardou entre parênteses ou com "ou" no próprio nome
    # ("ftalimidoglutarimida (talidomida)", "metandienona ou metandrostenolona").
    def build_index(substances)
      substances.each_with_object({}) do |substance, index|
        keys_for(substance.name).each { |key| index[key] ||= substance }
      end
    end

    def keys_for(name)
      names = [ name ] + name.split(/\s+ou\s+/)

      if (match = name.match(/\A(.+?)\s*\((.+)\)\s*\z/))
        names << match[1] << match[2]
        names += match[2].split(/\s+-\s+/)
      end

      names.flat_map { |value| [ normalize(value), normalize(value).delete(" ") ] }
           .reject { |key| key.length < 3 }
           .uniq
    end
  end
end
