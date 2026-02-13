defmodule Witness.Utils do
  @moduledoc false

  @doc """
  ## Examples

      iex> as_map(foo: "bar")
      %{foo: "bar"}

      iex> as_map(%{foo: "bar"})
      %{foo: "bar"}
  """
  @spec as_map(given) :: given when given: map
  def as_map(map) when is_map(map), do: map
  @spec as_map(keyword) :: map
  def as_map(list) when is_list(list), do: Map.new(list)

  @doc """
  ## Examples

      iex> as_map([foo: "bar"], [fizz: "buzz"])
      %{foo: "bar", fizz: "buzz"}

      iex> as_map([foo: "bar"], [foo: "bar2", fizz: "buzz"])
      %{foo: "bar2", fizz: "buzz"}

      iex> as_map([foo: "bar"], %{foo: "bar2", fizz: "buzz"})
      %{foo: "bar2", fizz: "buzz"}

      iex> as_map(%{foo: "bar"}, [foo: "bar2", fizz: "buzz"])
      %{foo: "bar2", fizz: "buzz"}

      iex> as_map(%{foo: "bar"}, %{foo: "bar2", fizz: "buzz"})
      %{foo: "bar2", fizz: "buzz"}
  """
  @spec as_map(map | keyword, extra :: map | keyword) :: merged_map when merged_map: map
  def as_map(map_or_list, extra), do: Enum.into(extra, as_map(map_or_list))

  @enriched_meta_key :__observability__
  @doc """
  ## Examples

      iex> enrich_meta(%{}, foo: "bar")
      %{#{@enriched_meta_key}: %{foo: "bar"}}

      iex> enrich_meta(%{#{@enriched_meta_key}: %{foo: "bar"}}, foo: "bazz")
      %{#{@enriched_meta_key}: %{foo: "bazz"}}

      iex> enrich_meta(%{some: "value"}, foo: "bazz")
      %{some: "value", #{@enriched_meta_key}: %{foo: "bazz"}}
  """
  @spec enrich_meta(map, at_key :: atom, kv :: keyword | map) :: map
  def enrich_meta(meta, at_key \\ @enriched_meta_key, kv) do
    meta = as_map(meta)
    kv = as_map(kv)

    Map.update(
      meta,
      at_key,
      kv,
      &Map.merge(&1, kv)
    )
  end

  @doc """
  ## Examples

      iex> pop_enriched_meta(%{#{@enriched_meta_key}: %{foo: "bar"}})
      {%{foo: "bar"}, %{}}

      iex> pop_enriched_meta(%{#{@enriched_meta_key}: %{foo: "bar"}, another: "field"})
      {%{foo: "bar"}, %{another: "field"}}

      iex> pop_enriched_meta(%{another: "field"})
      {%{}, %{another: "field"}}

      iex> pop_enriched_meta(%{#{@enriched_meta_key}: %{foo: "bar"}, another: %{map: "field"}}, :another)
      {%{map: "field"}, %{#{@enriched_meta_key}: %{foo: "bar"}}}
  """
  @spec pop_enriched_meta(meta, at_key :: atom) :: {enriched, meta} when enriched: map, meta: map
  def pop_enriched_meta(meta, at_key \\ @enriched_meta_key) do
    Map.pop(meta, at_key, %{})
  end

  @doc """
  ## Examples

      iex> flatten_map(%{foo: "bar"})
      %{"foo" => "bar"}

      iex> flatten_map(%{foo: %{bar: "baz", boing: "blubb"}})
      %{"foo.bar" => "baz", "foo.boing" => "blubb"}

      iex> flatten_map(%{foo: %{bar: "baz"}, foo2: [boing: "blubb"]})
      %{"foo.bar" => "baz", "foo2.boing" => "blubb"}

      iex> flatten_map(%{foo: %{bar: "baz"}, boing: "blubb"})
      %{"foo.bar" => "baz", "boing" => "blubb"}

      iex> flatten_map(%{foo: [bar: "baz"], boing: "blubb"})
      %{"foo.bar" => "baz", "boing" => "blubb"}

      iex> flatten_map(%{time: ~T[09:00:00]})
      %{"time" => ~T[09:00:00]}

      iex> flatten_map(%{foo: [bar: :baz], boing: [:blubb]}, &inspect/1)
      %{"foo.bar" => ":baz", "boing" => "[:blubb]"}
  """
  @spec flatten_map(map | keyword, transform :: (term -> term)) :: %{String.t() => not_a_map_or_keyword}
        when not_a_map_or_keyword: term
  def flatten_map(map_or_keyword, transform \\ & &1) do
    do_flatten(map_or_keyword, "", %{}, transform)
  end

  defp do_flatten(kv, prefix, into, transform) do
    Enum.reduce(kv, into, fn {key, value}, into ->
      prefixed_key = prefix <> to_string(key)

      if can_be_flattened?(value) do
        do_flatten(value, prefixed_key <> ".", into, transform)
      else
        Map.put(into, prefixed_key, transform.(value))
      end
    end)
  end

  defp can_be_flattened?(value) when is_map(value), do: not is_struct(value)
  defp can_be_flattened?(value), do: Keyword.keyword?(value)
end
