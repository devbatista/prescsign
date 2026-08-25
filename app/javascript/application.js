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

// Ao escolher um item do datalist de medicamentos, preenche os campos irmãos
// (princípio ativo, concentração, posologia) e vincula o medication_id.
function setupMedicationAutofill() {
  const datalist = document.getElementById("medications-list")
  if (!datalist) return
  if (document.body.dataset.medicationAutofillInitialized === "true") return
  document.body.dataset.medicationAutofillInitialized = "true"

  document.addEventListener("input", (event) => {
    const input = event.target.closest("[data-medication-name-input]")
    if (!input) return

    const option = Array.from(datalist.options).find((opt) => opt.value === input.value)
    if (!option) return

    const card = input.closest("[data-prescription-item-card]")
    if (!card) return

    const setField = (selector, value) => {
      const field = card.querySelector(selector)
      if (field && value) field.value = value
    }

    input.value = option.dataset.name || input.value
    setField("[data-medication-field='active-ingredient']", option.dataset.activeIngredient)
    setField("[data-medication-field='strength']", option.dataset.strength)
    setField("[data-medication-field='posology']", option.dataset.posology)

    const idField = card.querySelector("[data-medication-id-field]")
    if (idField) idField.value = option.dataset.medicationId || ""
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

    const select = form.querySelector("[data-delivery-channel-select]")
    const input = form.querySelector("[data-delivery-recipient-input]")
    const hint = form.querySelector("[data-delivery-recipient-hint]")
    const label = form.querySelector("[data-delivery-recipient-label]")

    if (!select || !input) return

    form.dataset.deliveryRecipientInitialized = "true"

    const currentKind = () =>
      select.selectedOptions[0]?.dataset.recipientKind === "phone" ? "phone" : "email"

    const applyKind = (kind, { keepValue }) => {
      if (!keepValue) input.value = ""
      input.dataset.recipientKind = kind
      input.dataset.lastDigitCount = String(countDigits(input.value))

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
    select.addEventListener("change", () => applyKind(currentKind(), { keepValue: false }))
    applyKind(currentKind(), { keepValue: true })
  })
}

document.addEventListener("DOMContentLoaded", setupConsultationDoctorFilters)
document.addEventListener("turbo:load", setupConsultationDoctorFilters)
document.addEventListener("DOMContentLoaded", setupSpecialtyFields)
document.addEventListener("turbo:load", setupSpecialtyFields)
document.addEventListener("DOMContentLoaded", setupPrescriptionItemFields)
document.addEventListener("turbo:load", setupPrescriptionItemFields)
document.addEventListener("DOMContentLoaded", setupMedicationAutofill)
document.addEventListener("turbo:load", setupMedicationAutofill)
document.addEventListener("DOMContentLoaded", setupDeliveryRecipientFields)
document.addEventListener("turbo:load", setupDeliveryRecipientFields)
