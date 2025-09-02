defmodule Lotus.Export.ValuePostgresTest do
  use ExUnit.Case, async: true

  alias Lotus.Export.Value

  describe "Postgrex.Range" do
    test "handles integer range with inclusive bounds" do
      range = %Postgrex.Range{
        lower: 1,
        upper: 10,
        lower_inclusive: true,
        upper_inclusive: false
      }

      assert Value.to_csv_string(range) == "[1,10)"
      assert Value.for_json(range) == "[1,10)"
    end

    test "handles date range" do
      range = %Postgrex.Range{
        lower: ~D[2024-01-01],
        upper: ~D[2024-12-31],
        lower_inclusive: true,
        upper_inclusive: true
      }

      assert Value.to_csv_string(range) == "[2024-01-01,2024-12-31]"
      assert Value.for_json(range) == "[2024-01-01,2024-12-31]"
    end

    test "handles range with nil/unbound" do
      range = %Postgrex.Range{
        lower: nil,
        upper: 100,
        lower_inclusive: false,
        upper_inclusive: false
      }

      assert Value.to_csv_string(range) == "(,100)"
    end

    test "handles range with unbound atom" do
      range = %Postgrex.Range{
        lower: :unbound,
        upper: 50,
        lower_inclusive: false,
        upper_inclusive: true
      }

      assert Value.to_csv_string(range) == "(,50]"
    end

    test "handles datetime range" do
      dt1 = ~U[2024-01-01 00:00:00Z]
      dt2 = ~U[2024-01-31 23:59:59Z]

      range = %Postgrex.Range{
        lower: dt1,
        upper: dt2,
        lower_inclusive: true,
        upper_inclusive: false
      }

      result = Value.to_csv_string(range)
      assert result =~ "2024-01-01"
      assert result =~ "2024-01-31"
      assert String.starts_with?(result, "[")
      assert String.ends_with?(result, ")")
    end
  end

  describe "Postgrex.INET" do
    test "handles IPv4 address without netmask" do
      inet = %Postgrex.INET{
        address: {192, 168, 1, 1},
        netmask: 32
      }

      assert Value.to_csv_string(inet) == "192.168.1.1"
      assert Value.for_json(inet) == "192.168.1.1"
    end

    test "handles IPv4 address with netmask" do
      inet = %Postgrex.INET{
        address: {192, 168, 0, 0},
        netmask: 24
      }

      assert Value.to_csv_string(inet) == "192.168.0.0/24"
      assert Value.for_json(inet) == "192.168.0.0/24"
    end

    test "handles IPv4 address with nil netmask" do
      inet = %Postgrex.INET{
        address: {10, 0, 0, 1},
        netmask: nil
      }

      assert Value.to_csv_string(inet) == "10.0.0.1"
    end

    test "handles IPv6 address" do
      inet = %Postgrex.INET{
        address: {0x2001, 0x0DB8, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0001},
        netmask: 128
      }

      result = Value.to_csv_string(inet)
      assert result =~ "2001"
      assert result =~ "DB8"
    end

    test "handles IPv6 address with netmask" do
      inet = %Postgrex.INET{
        address: {0x2001, 0x0DB8, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000},
        netmask: 64
      }

      result = Value.to_csv_string(inet)
      assert result =~ "/64"
    end
  end

  describe "Postgrex.Interval" do
    test "handles interval with all components" do
      interval = %Postgrex.Interval{
        # 1 year, 2 months
        months: 14,
        days: 3,
        # 1 hour, 1 minute, 1 second
        secs: 3661,
        microsecs: 0
      }

      assert Value.to_csv_string(interval) == "P1Y2M3DT1H1M1S"
      assert Value.for_json(interval) == "P1Y2M3DT1H1M1S"
    end

    test "handles zero interval" do
      interval = %Postgrex.Interval{
        months: 0,
        days: 0,
        secs: 0,
        microsecs: 0
      }

      assert Value.to_csv_string(interval) == "P0D"
      assert Value.for_json(interval) == "P0D"
    end

    test "handles interval with only days" do
      interval = %Postgrex.Interval{
        months: 0,
        days: 7,
        secs: 0,
        microsecs: 0
      }

      assert Value.to_csv_string(interval) == "P7D"
    end

    test "handles interval with only time" do
      interval = %Postgrex.Interval{
        months: 0,
        days: 0,
        # 2 hours
        secs: 7200,
        microsecs: 0
      }

      assert Value.to_csv_string(interval) == "PT2H"
    end

    test "handles interval with microseconds" do
      interval = %Postgrex.Interval{
        months: 0,
        days: 0,
        secs: 1,
        # 0.5 seconds
        microsecs: 500_000
      }

      assert Value.to_csv_string(interval) == "PT1.5S"
    end

    test "handles complex time interval" do
      # 2 hours, 30 minutes, 45 seconds
      interval = %Postgrex.Interval{
        months: 0,
        days: 0,
        secs: 9045,
        microsecs: 0
      }

      assert Value.to_csv_string(interval) == "PT2H30M45S"
    end

    test "handles years from months" do
      interval = %Postgrex.Interval{
        # 2 years, 1 month
        months: 25,
        days: 0,
        secs: 0,
        microsecs: 0
      }

      assert Value.to_csv_string(interval) == "P2Y1M"
    end
  end

  describe "Postgrex geometric types" do
    test "handles Point" do
      point = %Postgrex.Point{x: 1.5, y: 2.5}
      assert Value.to_csv_string(point) == "(1.5,2.5)"
    end

    test "handles Box" do
      upper_right = %Postgrex.Point{x: 10, y: 10}
      bottom_left = %Postgrex.Point{x: 0, y: 0}
      box = %Postgrex.Box{upper_right: upper_right, bottom_left: bottom_left}
      result = Value.to_csv_string(box)
      assert result =~ "10"
      assert result =~ "0"
    end

    test "handles LineSegment" do
      p1 = %Postgrex.Point{x: 0, y: 0}
      p2 = %Postgrex.Point{x: 5, y: 5}
      line = %Postgrex.LineSegment{point1: p1, point2: p2}
      result = Value.to_csv_string(line)
      assert result =~ "0"
      assert result =~ "5"
    end

    test "handles Path (open)" do
      points = [
        %Postgrex.Point{x: 0, y: 0},
        %Postgrex.Point{x: 1, y: 1},
        %Postgrex.Point{x: 2, y: 0}
      ]

      path = %Postgrex.Path{points: points, open: true}
      result = Value.to_csv_string(path)
      assert String.starts_with?(result, "[")
      assert String.ends_with?(result, "]")
      assert result =~ "1"
    end

    test "handles Path (closed)" do
      points = [
        %Postgrex.Point{x: 0, y: 0},
        %Postgrex.Point{x: 1, y: 1},
        %Postgrex.Point{x: 2, y: 0}
      ]

      path = %Postgrex.Path{points: points, open: false}
      result = Value.to_csv_string(path)
      assert String.starts_with?(result, "(")
      assert String.ends_with?(result, ")")
    end

    test "handles Polygon" do
      vertices = [
        %Postgrex.Point{x: 0, y: 0},
        %Postgrex.Point{x: 4, y: 0},
        %Postgrex.Point{x: 4, y: 3},
        %Postgrex.Point{x: 0, y: 3}
      ]

      polygon = %Postgrex.Polygon{vertices: vertices}
      result = Value.to_csv_string(polygon)
      assert result =~ "4"
      assert result =~ "3"
    end

    test "handles Circle" do
      center = %Postgrex.Point{x: 5, y: 5}
      circle = %Postgrex.Circle{center: center, radius: 3}
      result = Value.to_csv_string(circle)
      assert result =~ "5"
      assert result =~ "3"
    end
  end
end
