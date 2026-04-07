if Rails.env.development? && defined?(LetterOpenerWeb)
  letters_path = Pathname.new("/tmp/letter_opener")

  LetterOpenerWeb.configure do |config|
    config.letters_location = letters_path
  end

  if defined?(LetterOpener)
    LetterOpener.configure do |config|
      config.location = letters_path
    end
  end
end
