defmodule PhoenixKitCustomerSupport.CSPInlineTagsTest do
  @moduledoc """
  The pages of this module work under a host Content-Security-Policy that allows inline code
  by nonce only (`script-src 'self' 'nonce-…'`). The module renders no inline `<script>` /
  `<style>`, no inline event handler and ships no JavaScript; this test keeps it that way.

  A new inline tag takes the page's nonce through a feature-detecting
  `PhoenixKitCustomerSupport.Web.CSP` helper, which is added together with its first caller
  (see AGENTS.md, "Content-Security-Policy").

  Modelled on core's `test/phoenix_kit_web/csp_inline_tags_test.exs`.
  """
  use ExUnit.Case, async: true

  @doc_heredoc ~r/@(?:moduledoc|doc|typedoc|shortdoc)\s+(?:~[sS])?"""\n.*?\n\s*"""/s

  @tag_opening ~r/<(script|style)(?=[\s\/>])(?:[^>"']|"[^"]*"|'[^']*')*>/is
  @attribute ~r/([^\s=<>"'\/]+)(?:\s*=\s*("[^"]*"|'[^']*'|\{[^}]*\}|[^\s>]+))?/
  @nonce ~r/^\{\s*(?:PhoenixKitCustomerSupport\.Web\.)?CSP\.nonce\([^}]*\)\s*\}$/

  # Exempt: a colocated hook (`<script :type={Phoenix.LiveView.ColocatedHook}>`) is taken out
  # of the template by the compiler and is never rendered as an inline tag.
  test "no inline <script> or <style> in lib/ is written without a nonce" do
    offenders =
      for path <- Path.wildcard("lib/**/*.{ex,heex}"),
          {opening, number} <- tag_openings(path, @tag_opening),
          requires_nonce?(opening),
          do: "#{path}:#{number}"

    assert offenders == [],
           "inline tags without a nonce (feature-detect `PhoenixKitWeb.CSP.nonce/1`, " <>
             "see AGENTS.md, \"Content-Security-Policy\"):\n" <> Enum.join(offenders, "\n")
  end

  defp requires_nonce?(opening) do
    {tag, attrs} = tag_attributes(opening)

    external? = tag == "script" and Map.get(attrs, "src", "") != ""
    hook? = tag == "script" and attrs[":type"] == "{Phoenix.LiveView.ColocatedHook}"
    not (external? or hook? or Map.get(attrs, "nonce", "") =~ @nonce)
  end

  defp tag_attributes(opening) do
    [_, tag, rest] = Regex.run(~r/^<([^\s\/>]+)(.*)>$/s, opening)

    attrs =
      Map.new(Regex.scan(@attribute, rest), fn match ->
        {String.downcase(Enum.at(match, 1)), Enum.at(match, 2, "")}
      end)

    {String.downcase(tag), attrs}
  end

  test "only script sources, colocated hooks and nonce attributes exempt a tag" do
    assert requires_nonce?(~s[<STYLE data-src="theme">])
    assert requires_nonce?(~s[<script title="ColocatedHook CSP.nonce(assigns)">])
    refute requires_nonce?(~s[<SCRIPT SRC = "/app.js">])
    refute requires_nonce?(~s[<script :type={Phoenix.LiveView.ColocatedHook}>])
    refute requires_nonce?(~s[<style nonce={CSP.nonce(assigns)}>])
  end

  # `nonce={…}` is HEEx. In a plain string it is rendered as written, a literal attribute
  # the browser cannot match.
  test "a `nonce={…}` attribute in an .ex file sits inside a ~H template" do
    offenders =
      for path <- Path.wildcard("lib/**/*.ex"),
          lines = path |> File.read!() |> code_lines(),
          {line, number} <- lines,
          line =~ ~r/\bnonce\s*=\s*\{\s*(?:PhoenixKitCustomerSupport\.Web\.)?CSP\.nonce\(/i,
          not in_heex?(lines, number),
          do: "#{path}:#{number}"

    assert offenders == [], Enum.join(offenders, "\n")
  end

  # The nearest heredoc opener above the line is a `~H`.
  defp in_heex?(lines, number) do
    lines
    |> Enum.take(number - 1)
    |> Enum.reverse()
    |> Enum.find(fn {line, _} -> line =~ ~s(""") end)
    |> case do
      {opener, _} -> opener =~ ~s(~H""")
      nil -> false
    end
  end

  # Only the helper names core's module: it is newer than the core floor, and a direct call
  # anywhere else would not compile against the floor.
  test "PhoenixKitWeb.CSP is called through the feature-detecting helper only" do
    offenders =
      for path <- Path.wildcard("lib/**/*.{ex,heex}"),
          path != "lib/phoenix_kit_customer_support/web/csp.ex",
          {line, number} <- path |> File.read!() |> code_lines(),
          not (line =~ ~r/^\s*#/),
          line =~ ~r/PhoenixKitWeb\.CSP\.[a-z_]+\(/ or
            line =~ ~r/on_mount\(?\s*PhoenixKitWeb\.CSP\b/,
          do: "#{path}:#{number}"

    assert offenders == [], Enum.join(offenders, "\n")
  end

  @markup_tag ~r/<[a-z.][\w.:\-]*(?=[\s\/>])(?:[^<>"']|"[^"]*"|'[^']*')*>/is
  @js_url ~r/^["'{]?\s*["']?\s*javascript:/i

  defp inline_handler_or_url?(opening) do
    {_name, attrs} = tag_attributes(opening)

    Enum.any?(attrs, fn {name, value} ->
      (name != "only" and name =~ ~r/^on[a-z]+$/) or
        (name in ~w(href src action formaction) and value =~ @js_url)
    end)
  end

  test "no markup in lib/ carries an inline event handler or JavaScript URL" do
    offenders =
      for path <- Path.wildcard("lib/**/*.{ex,heex}"),
          {tag, number} <- tag_openings(path, @markup_tag),
          inline_handler_or_url?(tag),
          do: "#{path}:#{number}"

    assert offenders == [], Enum.join(offenders, "\n")
  end

  test "handler and URL patterns recognize HTML attribute syntax" do
    assert inline_handler_or_url?(~s[<ul onclick="x()">])
    assert inline_handler_or_url?(~s(<div onclick={@x}>))
    assert inline_handler_or_url?(~s(<img ONERROR\n = 'x'>))
    assert inline_handler_or_url?(~s[<a href="javascript:void(0)">])
    refute inline_handler_or_url?(~s(<button title=' onclick="sample"'>))
    refute inline_handler_or_url?(~s(<button phx-click="go">))
    refute inline_handler_or_url?(~s(<.table only={@only}>))
    refute inline_handler_or_url?(~s(<a data-href="javascript:">))
  end

  test "the module ships no JavaScript" do
    assert Path.wildcard("{lib,priv}/**/*.{js,mjs,cjs,ts,mts,cts}") == []

    module = Code.ensure_loaded!(PhoenixKitCustomerSupport)

    if function_exported?(module, :js_sources, 0) do
      assert module.js_sources() == []
    end
  end

  # Each matched opening tag and its starting line in the source file.
  defp tag_openings(path, pattern) do
    source = path |> File.read!() |> markup_source()

    for [{start, length}] <- Regex.scan(pattern, source, return: :index, capture: :first) do
      line = source |> binary_part(0, start) |> String.split("\n") |> length()
      {binary_part(source, start, length), line}
    end
  end

  # The source with what is not markup blanked, line numbers kept: documentation, HEEx
  # comments and Elixir comment lines (a tag there is prose).
  defp markup_source(source) do
    blank = fn text -> String.replace(text, ~r/[^\n]/, "") end

    source
    |> then(&Regex.replace(@doc_heredoc, &1, blank))
    |> then(&Regex.replace(~r/<%!--.*?--%>/s, &1, blank))
    |> then(&Regex.replace(~r/^[ \t]*#[^\n]*$/m, &1, ""))
  end

  defp code_lines(source) do
    @doc_heredoc
    |> Regex.replace(source, fn doc -> String.replace(doc, ~r/[^\n]/, "") end)
    |> String.split("\n")
    |> Enum.with_index(1)
  end
end
