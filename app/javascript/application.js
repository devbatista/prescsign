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

document.addEventListener("DOMContentLoaded", setupConsultationDoctorFilters)
document.addEventListener("turbo:load", setupConsultationDoctorFilters)
