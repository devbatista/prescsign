namespace :medications do
  desc "Importa/atualiza o catálogo de medicamentos a partir da Lista de Preços da CMED/Anvisa (idempotente). FILE=caminho usa um CSV local; URL=... troca a fonte."
  task import: :environment do
    path =
      if ENV["FILE"].present?
        Pathname.new(ENV["FILE"])
      else
        Medications::CmedCatalogImport.download!(url: ENV["URL"].presence || Medications::CmedCatalogImport::SOURCE_URL)
      end

    Medications::CmedCatalogImport.call(path: path)
  end
end
