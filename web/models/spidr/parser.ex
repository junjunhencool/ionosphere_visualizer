defmodule IonosphereVisualizer.SPIDR.Parser do
  import SweetXml

  @data_headers [:time, :value, :qualifier, :description]

  def parse_data(raw_data, :measurements) do
    raw_data
    |> StringIO.open
    |> elem(1)
    |> IO.stream(:line)
    |> Stream.reject(&(&1 == "\n"))
    |> Enum.to_list
    |> split_csv_data
    |> Stream.map(fn(csv) -> parse_single_csv(csv) end)
  end

  def parse_data(raw_data, :metadata) do
    raw_data
    |> xpath(~x"//metadata",
      code: ~x"//title/text()"s, name: ~x"//title/text()"s,
      date_from: ~x"//begdate/text()"s, date_to: ~x"//enddate/text()"s,
      location: [
        ~x"//bounding",
        longitude: ~x"./westbc/text()"s,
        latitude: ~x"./northbc/text()"s ])
    |> Map.update!(:location, &(%Geo.Point{ coordinates: { String.to_float(&1.longitude),
      String.to_float(&1.latitude) }, srid: nil }))
    |> Map.update!(:date_from, &(&1 <> "-12-31"))
    |> Map.update!(:date_to, &(case &1 do
        "Present" -> nil
        _ -> &1 <> "-01-01"
      end))
    |> Map.update!(:code, &(Regex.run(~r/\((.*?)\)/, &1) |> List.last))
    |> Map.update!(:name, &(Regex.replace(~r/\s*\((.*?)\)/, &1, "")))
  end

  def parse_data(raw_data, :station_list) do
    raw_data
    |> Floki.find("table a")
    |> Stream.map(&Floki.FlatText.get/1)
    |> Enum.take_every(2)
    #OPTIMIZE consider Stream
  end

  defp split_csv_data(csv_data) do
    {tl, hd} = csv_data
    |> List.foldl({[], []}, fn(line, {acc, tmp}) ->
      case String.first(line) do
        "#" when length(tmp) == 0 ->
          {acc, tmp}
        "#" when length(tmp) > 0 ->
          {[tmp | acc], []}
        _ -> 
          {acc, [line | tmp]}
      end
    end)

    [hd | tl]
    |> Enum.reverse
  end

  defp parse_single_csv(csv) do
    csv
    |> Stream.map(&(String.replace(&1, "/", "")))
    |> CSV.decode(headers: @data_headers, num_pipes: 1)
    |> Enum.map(&(Map.update!(&1, :value, fn(value) -> String.to_float(value) end)))
    #OPTIMIZE consider Stream
  end
end
