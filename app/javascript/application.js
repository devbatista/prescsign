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

document.addEventListener("DOMContentLoaded", setupConsultationDoctorFilters)
document.addEventListener("turbo:load", setupConsultationDoctorFilters)
document.addEventListener("DOMContentLoaded", setupSpecialtyFields)
document.addEventListener("turbo:load", setupSpecialtyFields)
