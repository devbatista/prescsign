# A suíte assume tabelas vazias: cada exemplo cria o que precisa e a transação de
# `use_transactional_fixtures` desfaz tudo no fim. Linhas que entraram por fora da
# suíte não são transacionais e sobrevivem a isso — um `db:seed` ou a carga do
# catálogo da CMED apontados para o banco de test deixam substância e medicamento
# gravados, e todo exemplo que cria registro de nome único passa a quebrar com
# "Name has already been taken".
#
# Zerar antes da suíte torna a execução independente do estado em que o banco de
# test foi deixado. TRUNCATE em tabela vazia é barato no Postgres, então a limpeza
# roda sempre, sem checar antes se há sujeira.
RSpec.configure do |config|
  config.before(:suite) do
    connection = ActiveRecord::Base.connection
    tables = connection.tables - %w[schema_migrations ar_internal_metadata]
    next if tables.empty?

    quoted = tables.map { |table| connection.quote_table_name(table) }.join(", ")
    connection.execute("TRUNCATE TABLE #{quoted} RESTART IDENTITY CASCADE")
  end
end
