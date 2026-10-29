local strings = Locales[Config.Locale] or Locales.en

function L(key)
    return strings[key] or Locales.en[key] or key
end

function UiStrings()
    return strings.ui or Locales.en.ui
end
