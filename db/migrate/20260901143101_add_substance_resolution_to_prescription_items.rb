class AddSubstanceResolutionToPrescriptionItems < ActiveRecord::Migration[7.1]
  def change
    # Como a classificação de controle deste item foi resolvida quando ele não veio
    # do catálogo (medication_id nulo). Sem isso, item digitado à mão não tinha de
    # onde derivar o tipo e a receita saía comum em silêncio, mesmo carregando
    # substância da 344/98 — ver docs/CLASSIFICACAO_CONTROLADA.md.
    #
    # substance_id: a substância que classifica o item, vinda do casamento
    # automático sobre o texto livre ou da identificação feita pelo médico.
    add_reference :prescription_items, :substance, type: :uuid, null: true, foreign_key: true

    # Quando o médico buscou na lista das 612 controladas e afirmou que nenhuma se
    # aplica. É o único caminho para item de texto livre sair como receita comum,
    # e fica registrado para a auditoria saber que houve afirmação, não omissão.
    add_column :prescription_items, :uncontrolled_confirmed_at, :datetime

    # Os dois campos são respostas mutuamente exclusivas à mesma pergunta: ou uma
    # substância classifica o item, ou o médico afirmou que nenhuma classifica.
    add_check_constraint :prescription_items,
                         "substance_id IS NULL OR uncontrolled_confirmed_at IS NULL",
                         name: "chk_prescription_items_single_control_resolution"
  end
end
