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

document.addEventListener("DOMContentLoaded", setupConsultationDoctorFilters)
document.addEventListener("turbo:load", setupConsultationDoctorFilters)
document.addEventListener("DOMContentLoaded", setupSpecialtyFields)
document.addEventListener("turbo:load", setupSpecialtyFields)
document.addEventListener("DOMContentLoaded", setupPrescriptionItemFields)
document.addEventListener("turbo:load", setupPrescriptionItemFields)
document.addEventListener("DOMContentLoaded", setupMedicationAutofill)
document.addEventListener("turbo:load", setupMedicationAutofill)
