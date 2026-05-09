defmodule PhoenixKitCustomerSupport.I18nTest do
  @moduledoc """
  Smoke test for the per-module i18n wiring.

  Confirms that:
    * Every tab registered by `PhoenixKitCustomerSupport.admin_tabs/0`,
      `settings_tabs/0`, and `user_dashboard_tabs/0` carries
      `gettext_backend: PhoenixKitCustomerSupport.Gettext`.
    * Locale switching on the module's own backend produces translated
      labels for at least one well-known msgid (regression guard for
      the `priv/gettext/<locale>/LC_MESSAGES/default.po` shipping with
      the package).
    * Falls back to the raw msgid for an unknown locale.
  """

  use ExUnit.Case, async: false

  # Excluded by `test/test_helper.exs` when running against a `phoenix_kit`
  # release that pre-dates the `gettext_backend` API (PR BeamLabEU/phoenix_kit#522).
  # Once the consumer's `phoenix_kit` dep resolves to a release that ships
  # `Tab.localized_label/1`, the helper detects it and these tests run
  # automatically — no follow-up edit needed.
  @moduletag :requires_phoenix_kit_i18n_api

  alias PhoenixKit.Dashboard.Tab
  alias PhoenixKitCustomerSupport
  alias PhoenixKitCustomerSupport.Gettext, as: CustomerSupportGettext

  setup do
    original = Gettext.get_locale(CustomerSupportGettext)
    on_exit(fn -> Gettext.put_locale(CustomerSupportGettext, original) end)
    :ok
  end

  describe "tab wiring" do
    test "every tab from every callback carries the module's own gettext backend" do
      tabs =
        PhoenixKitCustomerSupport.admin_tabs() ++
          PhoenixKitCustomerSupport.settings_tabs() ++
          PhoenixKitCustomerSupport.user_dashboard_tabs()

      # Sanity: catch a regression where a callback silently returns []
      # (which would make the for-loop a no-op and pass vacuously).
      assert length(tabs) >= 4,
             "expected at least 4 tabs across admin/settings/user_dashboard callbacks, got #{length(tabs)}"

      for tab <- tabs do
        assert tab.gettext_backend == CustomerSupportGettext,
               "Tab #{inspect(tab.id)} is missing or wrong gettext_backend " <>
                 "(got #{inspect(tab.gettext_backend)})"

        assert tab.gettext_domain == "default"
      end
    end
  end

  describe "Tab.localized_label/1 against the module's catalogue" do
    test "ru locale resolves the parent 'Customer Support' tab to 'Поддержка клиентов'" do
      Gettext.put_locale(CustomerSupportGettext, "ru")

      parent =
        Enum.find(PhoenixKitCustomerSupport.admin_tabs(), &(&1.id == :admin_customer_support))

      assert Tab.localized_label(parent) == "Поддержка клиентов"
    end

    test "et locale resolves the parent 'Customer Support' tab to 'Klienditugi'" do
      Gettext.put_locale(CustomerSupportGettext, "et")

      parent =
        Enum.find(PhoenixKitCustomerSupport.admin_tabs(), &(&1.id == :admin_customer_support))

      assert Tab.localized_label(parent) == "Klienditugi"
    end

    test "unknown locale falls back to the raw msgid" do
      Gettext.put_locale(CustomerSupportGettext, "zz")

      parent =
        Enum.find(PhoenixKitCustomerSupport.admin_tabs(), &(&1.id == :admin_customer_support))

      assert Tab.localized_label(parent) == parent.label
    end
  end
end
