module NavigationSpecHelpers
  def nav_link_for(path)
    Nokogiri::HTML(response.body).at_css(%(nav[aria-label="Navegação principal"] a[href="#{path}"]))
  end
end

RSpec.configure do |config|
  config.include NavigationSpecHelpers, type: :request
end
