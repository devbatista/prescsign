class OrganizationResponsible < ApplicationRecord
  belongs_to :organization
  belongs_to :doctor, optional: true
end
