# Postgres-specific type normalizers
# Only compiled when Postgrex types are available

if Code.ensure_loaded?(Postgrex.Range) do
  defimpl Lotus.Export.Normalizer, for: Postgrex.Range do
    def normalize(%Postgrex.Range{} = range) do
      lower_bound = if range.lower_inclusive, do: "[", else: "("
      upper_bound = if range.upper_inclusive, do: "]", else: ")"

      lower = format_range_value(range.lower)
      upper = format_range_value(range.upper)

      "#{lower_bound}#{lower},#{upper}#{upper_bound}"
    end

    defp format_range_value(nil), do: ""
    defp format_range_value(:unbound), do: ""

    defp format_range_value(value) do
      Lotus.Export.Normalizer.normalize(value)
    end
  end
end

if Code.ensure_loaded?(Postgrex.INET) do
  defimpl Lotus.Export.Normalizer, for: Postgrex.INET do
    def normalize(%Postgrex.INET{address: address, netmask: netmask}) do
      addr_str = format_address(address)

      case netmask do
        nil -> addr_str
        # IPv4 full mask
        32 -> addr_str
        # IPv6 full mask
        128 -> addr_str
        mask -> "#{addr_str}/#{mask}"
      end
    end

    defp format_address(address) when is_tuple(address) do
      case tuple_size(address) do
        # IPv4
        4 ->
          address |> Tuple.to_list() |> Enum.join(".")

        # IPv6
        8 ->
          address
          |> Tuple.to_list()
          |> Enum.map(&Integer.to_string(&1, 16))
          |> Enum.join(":")
      end
    end
  end
end

if Code.ensure_loaded?(Postgrex.Interval) do
  defimpl Lotus.Export.Normalizer, for: Postgrex.Interval do
    # Postgrex.Interval has: months, days, secs, microsecs
    def normalize(%Postgrex.Interval{} = interval) do
      parts = []

      # Convert months to years and months
      total_months = interval.months || 0
      years = div(total_months, 12)
      months = rem(total_months, 12)

      parts = if years != 0, do: parts ++ ["#{years}Y"], else: parts
      parts = if months != 0, do: parts ++ ["#{months}M"], else: parts

      parts =
        if interval.days && interval.days != 0, do: parts ++ ["#{interval.days}D"], else: parts

      # Handle time components (secs and microsecs)
      total_microsecs = (interval.secs || 0) * 1_000_000 + (interval.microsecs || 0)
      time_parts = format_time_parts(total_microsecs)

      duration_str =
        if time_parts == [] do
          parts
        else
          parts ++ ["T"] ++ time_parts
        end

      if duration_str == [] do
        # Zero duration
        "P0D"
      else
        "P" <> Enum.join(duration_str)
      end
    end

    defp format_time_parts(0), do: []

    defp format_time_parts(microsecs) do
      total_secs = div(microsecs, 1_000_000)
      remaining_microsecs = rem(microsecs, 1_000_000)

      hours = div(total_secs, 3600)
      minutes = div(rem(total_secs, 3600), 60)
      seconds = rem(total_secs, 60)

      parts = []

      parts =
        if seconds != 0 or remaining_microsecs != 0 do
          if remaining_microsecs != 0 do
            # Format with fractional seconds
            frac_seconds = seconds + remaining_microsecs / 1_000_000
            parts ++ ["#{Float.to_string(frac_seconds)}S"]
          else
            parts ++ ["#{seconds}S"]
          end
        else
          parts
        end

      parts = if minutes != 0, do: ["#{minutes}M"] ++ parts, else: parts
      parts = if hours != 0, do: ["#{hours}H"] ++ parts, else: parts

      parts
    end
  end
end

if Code.ensure_loaded?(Postgrex.Point) do
  defimpl Lotus.Export.Normalizer, for: Postgrex.Point do
    def normalize(%Postgrex.Point{x: x, y: y}) do
      "(#{x},#{y})"
    end
  end
end

if Code.ensure_loaded?(Postgrex.LineSegment) do
  defimpl Lotus.Export.Normalizer, for: Postgrex.LineSegment do
    def normalize(%Postgrex.LineSegment{point1: p1, point2: p2}) do
      "[#{Lotus.Export.Normalizer.normalize(p1)},#{Lotus.Export.Normalizer.normalize(p2)}]"
    end
  end
end

if Code.ensure_loaded?(Postgrex.Box) do
  defimpl Lotus.Export.Normalizer, for: Postgrex.Box do
    def normalize(%Postgrex.Box{upper_right: ur, bottom_left: bl}) do
      "(#{Lotus.Export.Normalizer.normalize(ur)},#{Lotus.Export.Normalizer.normalize(bl)})"
    end
  end
end

if Code.ensure_loaded?(Postgrex.Path) do
  defimpl Lotus.Export.Normalizer, for: Postgrex.Path do
    def normalize(%Postgrex.Path{points: points, open: open}) do
      points_str =
        points
        |> Enum.map(&Lotus.Export.Normalizer.normalize/1)
        |> Enum.join(",")

      if open do
        "[#{points_str}]"
      else
        "(#{points_str})"
      end
    end
  end
end

if Code.ensure_loaded?(Postgrex.Polygon) do
  defimpl Lotus.Export.Normalizer, for: Postgrex.Polygon do
    def normalize(%Postgrex.Polygon{vertices: vertices}) do
      points_str =
        vertices
        |> Enum.map(&Lotus.Export.Normalizer.normalize/1)
        |> Enum.join(",")

      "(#{points_str})"
    end
  end
end

if Code.ensure_loaded?(Postgrex.Circle) do
  defimpl Lotus.Export.Normalizer, for: Postgrex.Circle do
    def normalize(%Postgrex.Circle{center: center, radius: radius}) do
      "<#{Lotus.Export.Normalizer.normalize(center)},#{radius}>"
    end
  end
end
