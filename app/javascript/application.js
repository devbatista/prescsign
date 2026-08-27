// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails

function setupConsultationDoctorFilters() {
  document.querySelectorAll("[data-consultation-doctor-filter]").forEach((container) => {
    if (container.dataset.consultationDoctorFilterInitialized === "true") return

    const specialtySelect = container.querySelector("[data-consultation-specialty-select]")
    const doctorField = container.querySelector("[data-consultation-doctor-field]")
    const doctorSelect = container.querySelector("[data-consultation-doctor-select]")

    if (!specialtySelect || !doctorField || !doctorSelect) return

    container.dataset.consultationDoctorFilterInitialized = "true"

    const blankOption = doctorSelect.querySelector("option[value='']")?.cloneNode(true)
    const doctorOptions = Array.from(doctorSelect.options)
      .filter((option) => option.value !== "")
      .map((option) => option.cloneNode(true))

    const updateDoctorOptions = () => {
      const specialtyId = specialtySelect.value
      const currentDoctorId = doctorSelect.value
      const hasSpecialty = specialtyId !== ""

      doctorField.classList.toggle("hidden", !hasSpecialty)
      doctorSelect.disabled = !hasSpecialty
      doctorSelect.replaceChildren()

      if (blankOption) doctorSelect.appendChild(blankOption.cloneNode(true))
      if (!hasSpecialty) return

      doctorOptions.forEach((option) => {
        const specialtyIds = (option.dataset.specialtyIds || "").split(",").filter(Boolean)
        if (specialtyIds.includes(specialtyId)) doctorSelect.appendChild(option.cloneNode(true))
      })

      if (Array.from(doctorSelect.options).some((option) => option.value === currentDoctorId)) {
        doctorSelect.value = currentDoctorId
      } else {
        doctorSelect.value = ""
      }
    }

    specialtySelect.addEventListener("change", updateDoctorOptions)
    updateDoctorOptions()
  })
}

function setupSpecialtyFields() {
  document.querySelectorAll("[data-specialty-fields]").forEach((container) => {
    if (container.dataset.specialtyFieldsInitialized === "true") return

    const list = container.querySelector("[data-specialty-fields-list]")
    const template = container.querySelector("[data-specialty-template]")
    const addButton = container.querySelector("[data-add-specialty]")

    if (!list || !template || !addButton) return

    container.dataset.specialtyFieldsInitialized = "true"
    let nextIndex = Date.now()

    const updateRemoveButtons = () => {
      const cards = list.querySelectorAll("[data-specialty-card]")
      cards.forEach((card) => {
        const removeButton = card.querySelector("[data-remove-specialty]")
        if (removeButton) removeButton.classList.toggle("hidden", cards.length <= 1)
      })
    }

    addButton.addEventListener("click", () => {
      const index = (nextIndex += 1).toString()
      const wrapper = document.createElement("div")
      wrapper.innerHTML = template.innerHTML.replace(/NEW_RECORD/g, index).trim()
      const card = wrapper.firstElementChild

      if (card) list.appendChild(card)
      updateRemoveButtons()
    })

    list.addEventListener("click", (event) => {
      const removeButton = event.target.closest("[data-remove-specialty]")
      if (!removeButton) return

      const card = removeButton.closest("[data-specialty-card]")
      if (!card || list.querySelectorAll("[data-specialty-card]").length <= 1) return

      card.remove()
      updateRemoveButtons()
    })

    updateRemoveButtons()
  })
}

function setupPrescriptionItemFields() {
  document.querySelectorAll("[data-prescription-item-fields]").forEach((container) => {
    if (container.dataset.prescriptionItemFieldsInitialized === "true") return

    const list = container.querySelector("[data-prescription-item-fields-list]")
    const template = container.querySelector("[data-prescription-item-template]")
    const addButton = container.querySelector("[data-add-prescription-item]")

    if (!list || !template || !addButton) return

    container.dataset.prescriptionItemFieldsInitialized = "true"
    let nextIndex = Date.now()

    addButton.addEventListener("click", () => {
      const index = (nextIndex += 1).toString()
      const wrapper = document.createElement("div")
      wrapper.innerHTML = template.innerHTML.replace(/NEW_RECORD/g, index).trim()
      const card = wrapper.firstElementChild
      if (card) list.appendChild(card)
    })

    list.addEventListener("click", (event) => {
      const removeButton = event.target.closest("[data-remove-prescription-item]")
      if (!removeButton) return

      const card = removeButton.closest("[data-prescription-item-card]")
      if (!card) return

      const destroyField = card.querySelector("input[type='checkbox'][name*='_destroy']")
      if (destroyField) {
        // Item persistido: marca para remoção e esconde, preservando o hidden.
        destroyField.checked = true
        card.classList.add("hidden")
      } else {
        card.remove()
      }
    })
  })
}

// Busca de medicamento no catálogo. O catálogo tem dezenas de milhares de
// apresentações, então quem busca é o servidor (app/medications#search) — mandar
// tudo no HTML custava megabytes por render. Cada resultado mostra fabricante e
// apresentação porque milhares de produtos dividem o mesmo "nome + concentração"
// e o item precisa apontar para UM deles: é o medication_id que decide o tipo
// SNCR da receita. Por isso, digitar à mão desfaz o vínculo.
const MEDICATION_SEARCH_DEBOUNCE = 250
const MEDICATION_MIN_QUERY = 2

// Resultados da última busca de cada campo (o <li> guarda só o índice).
const medicationResults = new WeakMap()

function medicationParts(medication) {
  return [medication.presentation, medication.manufacturer].filter(Boolean).join(" · ")
}

function medicationBadge(medication) {
  if (medication.sncr_type) return `Controlado · ${medication.sncr_type}`
  if (medication.control_class === "tarja_vermelha_retencao") return "Tarja vermelha com retenção"
  if (medication.control_class === "tarja_vermelha") return "Tarja vermelha"
  if (medication.control_class === "tarja_preta") return "Tarja preta"
  return ""
}

function closeMedicationResults(list) {
  if (!list) return
  list.classList.add("hidden")
  list.replaceChildren()
}

// Busca que não respondeu não é busca sem resultado: dizer "nada encontrado"
// quando o servidor falhou manda o médico digitar à mão achando que o produto
// não existe no catálogo.
function renderMedicationFailure(list) {
  medicationResults.set(list, [])
  list.replaceChildren()

  const failure = document.createElement("li")
  failure.className = "px-3 py-2 text-sm text-ps-error-fg"
  failure.textContent = "Não foi possível buscar no catálogo agora. Tente de novo em instantes."
  list.append(failure)
  list.classList.remove("hidden")
}

function renderMedicationResults(list, medications) {
  medicationResults.set(list, medications)
  list.replaceChildren()

  if (medications.length === 0) {
    const empty = document.createElement("li")
    empty.className = "px-3 py-2 text-sm text-ps-slate-500"
    empty.textContent = "Nada encontrado no catálogo — você pode digitar manualmente."
    list.append(empty)
    list.classList.remove("hidden")
    return
  }

  medications.forEach((medication, index) => {
    const item = document.createElement("li")
    item.className = "cursor-pointer px-3 py-2 text-sm hover:bg-[#eef4ff]"
    item.dataset.medicationResult = String(index)
    item.setAttribute("role", "option")

    const title = document.createElement("span")
    title.className = "block font-medium text-ps-slate-900"
    title.textContent = medication.label || medication.name
    item.append(title)

    const detail = medicationParts(medication)
    if (detail) {
      const line = document.createElement("span")
      line.className = "block truncate text-xs text-ps-slate-500"
      line.textContent = detail
      item.append(line)
    }

    const badge = medicationBadge(medication)
    if (badge) {
      const tag = document.createElement("span")
      tag.className = "mt-0.5 block text-xs font-semibold text-[#4a6b93]"
      tag.textContent = badge
      item.append(tag)
    }

    list.append(item)
  })

  list.classList.remove("hidden")
}

function applyMedication(card, medication) {
  const setField = (selector, value) => {
    const field = card.querySelector(selector)
    if (field && value) field.value = value
  }

  const nameInput = card.querySelector("[data-medication-name-input]")
  if (nameInput) nameInput.value = medication.name || nameInput.value

  setField("[data-medication-field='active-ingredient']", medication.active_ingredient)
  setField("[data-medication-field='strength']", medication.strength)
  setField("[data-medication-field='posology']", medication.posology)

  const idField = card.querySelector("[data-medication-id-field]")
  if (idField) idField.value = medication.id || ""

  const selected = card.querySelector("[data-medication-selected]")
  if (selected) {
    const badge = medicationBadge(medication)
    selected.textContent = [medicationParts(medication), badge].filter(Boolean).join(" · ")
    selected.classList.toggle("hidden", selected.textContent === "")
  }
}

// Item digitado à mão não é item do catálogo: solta o vínculo em vez de manter
// um medication_id que não corresponde ao que está escrito.
function unlinkMedication(card) {
  const idField = card.querySelector("[data-medication-id-field]")
  if (idField) idField.value = ""

  const selected = card.querySelector("[data-medication-selected]")
  if (selected) {
    selected.textContent = ""
    selected.classList.add("hidden")
  }
}

function highlightMedicationResult(list, delta) {
  const items = Array.from(list.querySelectorAll("[data-medication-result]"))
  if (items.length === 0) return

  const current = items.findIndex((item) => item.dataset.highlighted === "true")
  const next = (current + delta + items.length + (current === -1 && delta < 0 ? 1 : 0)) % items.length

  items.forEach((item, index) => {
    const active = index === next
    item.dataset.highlighted = active ? "true" : "false"
    item.classList.toggle("bg-[#eef4ff]", active)
    if (active) item.scrollIntoView({ block: "nearest" })
  })
}

function setupMedicationSearch() {
  if (document.body.dataset.medicationSearchInitialized === "true") return
  document.body.dataset.medicationSearchInitialized = "true"

  let timer = null

  document.addEventListener("input", (event) => {
    const input = event.target.closest("[data-medication-name-input]")
    if (!input) return

    const wrapper = input.closest("[data-medication-search]")
    const card = input.closest("[data-prescription-item-card]")
    if (!wrapper || !card) return

    const list = wrapper.querySelector("[data-medication-results]")
    unlinkMedication(card)

    const query = input.value.trim()
    window.clearTimeout(timer)

    if (query.length < MEDICATION_MIN_QUERY) return closeMedicationResults(list)

    timer = window.setTimeout(() => {
      const url = `${wrapper.dataset.medicationSearchUrl}?q=${encodeURIComponent(query)}`

      fetch(url, { headers: { Accept: "application/json" } })
        .then((response) => {
          if (!response.ok) throw new Error(`busca falhou (HTTP ${response.status})`)
          return response.json()
        })
        .then((payload) => {
          // A resposta pode chegar depois de o médico continuar digitando.
          if (input.value.trim() !== query) return
          renderMedicationResults(list, payload.results || [])
        })
        .catch((error) => {
          if (input.value.trim() !== query) return
          console.error("Catálogo de medicamentos:", error)
          renderMedicationFailure(list)
        })
    }, MEDICATION_SEARCH_DEBOUNCE)
  })

  // mousedown, não click: o blur do campo fecharia a lista antes do click.
  document.addEventListener("mousedown", (event) => {
    const option = event.target.closest("[data-medication-result]")

    if (!option) {
      if (!event.target.closest("[data-medication-search]")) {
        document.querySelectorAll("[data-medication-results]").forEach(closeMedicationResults)
      }
      return
    }

    event.preventDefault()
    const list = option.closest("[data-medication-results]")
    const card = option.closest("[data-prescription-item-card]")
    const medication = (medicationResults.get(list) || [])[Number(option.dataset.medicationResult)]
    if (!medication || !card) return

    applyMedication(card, medication)
    closeMedicationResults(list)
  })

  document.addEventListener("keydown", (event) => {
    const input = event.target.closest("[data-medication-name-input]")
    if (!input) return

    const wrapper = input.closest("[data-medication-search]")
    const list = wrapper?.querySelector("[data-medication-results]")
    if (!list || list.classList.contains("hidden")) return

    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      highlightMedicationResult(list, event.key === "ArrowDown" ? 1 : -1)
    } else if (event.key === "Enter") {
      const option = list.querySelector("[data-medication-result][data-highlighted='true']")
      if (!option) return

      event.preventDefault()
      const card = input.closest("[data-prescription-item-card]")
      const medication = (medicationResults.get(list) || [])[Number(option.dataset.medicationResult)]
      if (medication && card) applyMedication(card, medication)
      closeMedicationResults(list)
    } else if (event.key === "Escape") {
      closeMedicationResults(list)
    }
  })
}

// O campo de destinatário do reenvio serve dois canais com formatos opostos.
// Em vez de um texto livre que só falha no provedor, ele se molda ao canal
// escolhido: e-mail valida como e-mail; WhatsApp aceita dígitos e formata.
const PHONE_MAX_DIGITS = 13 // DDI (2) + DDD (2) + assinante (9)

function countDigits(value) {
  return (value.match(/\d/g) || []).length
}

// Só trata os dois primeiros dígitos como DDI quando sobra número nacional
// completo — "55987654321" é um celular do DDD 55, não um +55 truncado.
function formatBrazilianPhone(digits) {
  let rest = digits.slice(0, PHONE_MAX_DIGITS)
  let prefix = ""

  if (rest.length > 11 && rest.startsWith("55")) {
    prefix = "+55 "
    rest = rest.slice(2)
  }

  if (rest.length === 0) return prefix.trim()
  if (rest.length <= 2) return `${prefix}(${rest}`

  const area = rest.slice(2)
  const split = rest.length > 10 ? 5 : 4
  if (area.length <= split) return `${prefix}(${rest.slice(0, 2)}) ${area}`

  return `${prefix}(${rest.slice(0, 2)}) ${area.slice(0, split)}-${area.slice(split)}`
}

function setCaretAfterDigits(input, digitsBefore) {
  if (digitsBefore === 0) return input.setSelectionRange(0, 0)

  let seen = 0
  for (let i = 0; i < input.value.length; i++) {
    if (!/\d/.test(input.value[i])) continue
    seen += 1
    if (seen === digitsBefore) return input.setSelectionRange(i + 1, i + 1)
  }

  input.setSelectionRange(input.value.length, input.value.length)
}

function setupDeliveryRecipientFields() {
  document.querySelectorAll("[data-delivery-recipient]").forEach((form) => {
    if (form.dataset.deliveryRecipientInitialized === "true") return

    const radios = form.querySelectorAll("[data-delivery-channel-radio]")
    const input = form.querySelector("[data-delivery-recipient-input]")
    const hint = form.querySelector("[data-delivery-recipient-hint]")
    const label = form.querySelector("[data-delivery-recipient-label]")

    if (radios.length === 0 || !input) return

    form.dataset.deliveryRecipientInitialized = "true"

    const currentKind = () =>
      form.querySelector("[data-delivery-channel-radio]:checked")?.dataset.recipientKind === "phone"
        ? "phone"
        : "email"

    const applyKind = (kind, { keepValue }) => {
      if (!keepValue) input.value = ""
      input.dataset.recipientKind = kind
      input.dataset.lastDigitCount = String(countDigits(input.value))

      form.querySelectorAll("[data-delivery-recipient-icon]").forEach((icon) => {
        icon.classList.toggle("hidden", icon.dataset.deliveryRecipientIcon !== kind)
      })

      if (kind === "phone") {
        input.type = "tel"
        input.inputMode = "numeric"
        input.autocomplete = "tel"
        input.maxLength = 19
        input.placeholder = "(11) 91234-5678"
        input.pattern = "(\\+55\\s)?\\(\\d{2}\\)\\s\\d{4,5}-\\d{4}"
        input.title = "Informe DDD e número, ex.: (11) 91234-5678"
        if (label) label.textContent = "WhatsApp do destinatário (opcional)"
        if (hint) hint.textContent = "Deixe vazio para usar o WhatsApp cadastrado do paciente."
      } else {
        input.type = "email"
        input.inputMode = "email"
        input.autocomplete = "email"
        input.removeAttribute("maxlength")
        input.removeAttribute("pattern")
        input.placeholder = "paciente@exemplo.com"
        input.title = "Informe um e-mail válido, ex.: paciente@exemplo.com"
        if (label) label.textContent = "E-mail do destinatário (opcional)"
        if (hint) hint.textContent = "Deixe vazio para usar o e-mail cadastrado do paciente."
      }
    }

    input.addEventListener("input", (event) => {
      if (input.dataset.recipientKind !== "phone") return

      const caret = input.selectionStart ?? input.value.length
      let digitsBefore = countDigits(input.value.slice(0, caret))
      let digits = input.value.replace(/\D/g, "")

      // Apagar um separador não pode travar o campo: a formatação o devolveria
      // intacto, então a tecla apaga o dígito anterior a ele.
      const deleting = (event.inputType || "").startsWith("delete")
      if (deleting && digitsBefore > 0 && digits.length === Number(input.dataset.lastDigitCount)) {
        digits = digits.slice(0, digitsBefore - 1) + digits.slice(digitsBefore)
        digitsBefore -= 1
      }

      input.value = formatBrazilianPhone(digits)
      input.dataset.lastDigitCount = String(countDigits(input.value))
      setCaretAfterDigits(input, digitsBefore)
    })

    // Troca de canal descarta o destinatário anterior: um e-mail sobrando no
    // campo de WhatsApp seria enviado como se fosse número.
    radios.forEach((radio) => {
      radio.addEventListener("change", () => applyKind(currentKind(), { keepValue: false }))
    })
    applyKind(currentKind(), { keepValue: true })
  })
}

document.addEventListener("DOMContentLoaded", setupConsultationDoctorFilters)
document.addEventListener("turbo:load", setupConsultationDoctorFilters)
document.addEventListener("DOMContentLoaded", setupSpecialtyFields)
document.addEventListener("turbo:load", setupSpecialtyFields)
document.addEventListener("DOMContentLoaded", setupPrescriptionItemFields)
document.addEventListener("turbo:load", setupPrescriptionItemFields)
document.addEventListener("DOMContentLoaded", setupMedicationSearch)
document.addEventListener("turbo:load", setupMedicationSearch)
document.addEventListener("DOMContentLoaded", setupDeliveryRecipientFields)
document.addEventListener("turbo:load", setupDeliveryRecipientFields)
