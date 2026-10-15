# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cpf, :cnpj,
  :pin, :content, :pdf_base64, :session_id
]

# Dado pessoal e dado de saúde do paciente (LGPD, art. 11). Os parâmetros vão
# para o log de produção e para os breadcrumbs do Sentry em texto puro, então
# o que identifica o paciente ou revela a condição clínica dele não pode passar.
#
# - Identificação: nome, nascimento, telefone, destinatário do envio e o e-mail
#   do paciente. O e-mail do médico continua visível de propósito — é o que se
#   procura no log ao depurar login.
# - Clínico: CID do atestado, queixa, anotações e diagnóstico da consulta, e o
#   que foi prescrito. O nome do item da receita é filtrado pelo caminho, porque
#   `name` sozinho pegaria nome de organização, de especialidade etc.
# - Busca (`q`): na tela de pacientes, é o nome do paciente digitado.
Rails.application.config.filter_parameters += [
  :full_name, :birth_date, :phone, :recipient, "patient.email",
  :icd_code, :chief_complaint, :notes, :diagnosis,
  :active_ingredient, :posology, /prescription_items_attributes\.(?:\d+\.)?name\z/,
  /\Aq\z/
]
