defmodule Witness.UtilsTest do
  use ExUnit.Case, async: true

  alias Witness.Utils
  import Witness.Utils

  doctest Utils

  describe "as_map/1" do
    test "converts keyword list to map" do
      assert Utils.as_map(foo: "bar") == %{foo: "bar"}
    end

    test "returns map as-is" do
      assert Utils.as_map(%{foo: "bar"}) == %{foo: "bar"}
    end
  end

  describe "as_map/2" do
    test "merges keyword lists" do
      assert Utils.as_map([foo: "bar"], [fizz: "buzz"]) == %{foo: "bar", fizz: "buzz"}
    end

    test "second argument overwrites first" do
      assert Utils.as_map([foo: "bar"], [foo: "bar2"]) == %{foo: "bar2"}
    end

    test "merges map and keyword list" do
      assert Utils.as_map(%{foo: "bar"}, [foo: "bar2", fizz: "buzz"]) == %{
               foo: "bar2",
               fizz: "buzz"
             }
    end
  end

  describe "enrich_meta/3" do
    test "adds enriched metadata at default key" do
      result = Utils.enrich_meta(%{}, foo: "bar")
      assert result == %{__observability__: %{foo: "bar"}}
    end

    test "merges with existing enriched metadata" do
      meta = %{__observability__: %{foo: "bar"}}
      result = Utils.enrich_meta(meta, foo: "bazz")
      assert result == %{__observability__: %{foo: "bazz"}}
    end

    test "adds enriched metadata at custom key" do
      result = Utils.enrich_meta(%{some: "value"}, :custom_key, foo: "bazz")
      assert result == %{some: "value", custom_key: %{foo: "bazz"}}
    end

    test "preserves other metadata" do
      result = Utils.enrich_meta(%{some: "value"}, foo: "bazz")
      assert result == %{some: "value", __observability__: %{foo: "bazz"}}
    end
  end

  describe "pop_enriched_meta/2" do
    test "pops enriched metadata at default key" do
      meta = %{__observability__: %{foo: "bar"}}
      assert Utils.pop_enriched_meta(meta) == {%{foo: "bar"}, %{}}
    end

    test "preserves other fields when popping" do
      meta = %{__observability__: %{foo: "bar"}, another: "field"}
      assert Utils.pop_enriched_meta(meta) == {%{foo: "bar"}, %{another: "field"}}
    end

    test "returns empty map for enriched when key doesn't exist" do
      meta = %{another: "field"}
      assert Utils.pop_enriched_meta(meta) == {%{}, %{another: "field"}}
    end

    test "pops enriched metadata at custom key" do
      meta = %{__observability__: %{foo: "bar"}, another: %{map: "field"}}
      assert Utils.pop_enriched_meta(meta, :another) == {%{map: "field"}, %{__observability__: %{foo: "bar"}}}
    end
  end

  describe "flatten_map/2" do
    test "flattens single level map" do
      assert Utils.flatten_map(%{foo: "bar"}) == %{"foo" => "bar"}
    end

    test "flattens nested map" do
      assert Utils.flatten_map(%{foo: %{bar: "baz"}}) == %{"foo.bar" => "baz"}
    end

    test "flattens mixed map and keyword list" do
      result = Utils.flatten_map(%{foo: %{bar: "baz"}, foo2: [boing: "blubb"]})
      assert result == %{"foo.bar" => "baz", "foo2.boing" => "blubb"}
    end

    test "preserves non-map values" do
      assert Utils.flatten_map(%{foo: %{bar: "baz"}, boing: "blubb"}) == %{
               "foo.bar" => "baz",
               "boing" => "blubb"
             }
    end

    test "flattens keyword lists" do
      assert Utils.flatten_map(%{foo: [bar: "baz"], boing: "blubb"}) == %{
               "foo.bar" => "baz",
               "boing" => "blubb"
             }
    end

    test "preserves struct values" do
      time = ~T[09:00:00]
      assert Utils.flatten_map(%{time: time}) == %{"time" => time}
    end

    test "applies transform function" do
      result = Utils.flatten_map(%{foo: [bar: :baz], boing: [:blubb]}, &inspect/1)
      assert result == %{"foo.bar" => ":baz", "boing" => "[:blubb]"}
    end
  end
end
