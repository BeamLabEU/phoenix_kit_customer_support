# Dialyzer warnings to ignore (matched by dialyxir).
#
# Gettext 1.0 + Expo 1.1 generate a `Gettext.Plural.plural/2` call against Expo's
# *opaque* `PluralForms` struct inside the generated backend (`use Gettext.Backend`),
# which Dialyzer reports as `call_without_opaque` at `gettext.ex:1` once the backend
# has a catalogue with plural forms (the guest-link email's ngettext). A known
# upstream false positive in code we do not author, scoped to the backend module and
# that warning type only — the same skip the other `phoenix_kit_*` packages carry.
[
  {"lib/phoenix_kit_customer_support/gettext.ex", :call_without_opaque}
]
