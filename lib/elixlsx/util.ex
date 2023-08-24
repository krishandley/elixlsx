defmodule Elixlsx.Util do
  alias Elixlsx.XML
  @col_alphabet Enum.to_list(?A..?Z)
  @padding 5
  @col_width 8.43
  @row_height 15

  @doc ~S"""
  Returns the column letter(s) associated with a column index.

  Col idx starts at 1.

  ## Examples

      iex> encode_col(1)
      "A"

      iex> encode_col(28)
      "AB"

  """
  @spec encode_col(non_neg_integer) :: String.t()
  def encode_col(0), do: ""
  def encode_col(num) when num <= 26, do: <<num + 64>>

  def encode_col(num, suffix \\ "")
  def encode_col(num, suffix) when num <= 26, do: <<num + 64>> <> suffix

  def encode_col(num, suffix) do
    mod = div(num, 26)
    rem = rem(num, 26)

    if rem == 0 do
      encode_col(mod - 1, "Z" <> suffix)
    else
      encode_col(mod, <<rem + 64>> <> suffix)
    end
  end

  @doc ~S"""
  Returns the column index associated with a given letter.

  ## Examples

      iex> decode_col("AB")
      28

      iex> decode_col("A")
      1

  """
  @spec decode_col(list(char()) | String.t()) :: non_neg_integer
  def decode_col(s) when is_list(s), do: decode_col(to_string(s))
  def decode_col(""), do: 0

  def decode_col(s) when is_binary(s) do
    case String.match?(s, ~r/^[A-Z]*$/) do
      false ->
        raise %ArgumentError{message: "Invalid column string: " <> inspect(s)}

      true ->
        # translate list of strings to the base-26 value they represent
        Enum.map(String.to_charlist(s), fn x -> :string.chr(@col_alphabet, x) end)
        # multiply and aggregate them
        |> List.foldl(0, fn x, acc -> x + 26 * acc end)
    end
  end

  def decode_col(s) do
    raise %ArgumentError{message: "decode_col expects string or charlist, got " <> inspect(s)}
  end

  @doc ~S"""
  Returns the Char/Number representation of a given row/column combination.

  Indizes start with 1.

  ## Examples

      iex> to_excel_coords(1, 1)
      "A1"

      iex> to_excel_coords(10, 27)
      "AA10"

  """
  @spec to_excel_coords(number, number) :: String.t()
  def to_excel_coords(row, col) do
    encode_col(col) <> to_string(row)
  end

  @spec from_excel_coords(String.t()) :: {pos_integer, pos_integer}
  @doc ~S"""
  Returns a tuple {row, col} corresponding to the input.

  Row and col are 1-indexed, use from_excel_coords0 for zero-indexing.

  ## Examples

      iex> from_excel_coords("C2")
      {2, 3}

      iex> from_excel_coords0("C2")
      {1, 2}

  """
  def from_excel_coords(input) do
    case Regex.run(~r/^([A-Z]+)([0-9]+)$/, input, capture: :all_but_first) do
      nil ->
        raise %ArgumentError{message: "Invalid excel coordinates: " <> inspect(input)}

      [colS, rowS] ->
        {row, _} = Integer.parse(rowS)
        {row, decode_col(colS)}
    end
  end

  @spec from_excel_coords0(String.t()) :: {non_neg_integer, non_neg_integer}
  @doc ~S"See from_excel_coords/1"
  def from_excel_coords0(input) do
    {row, col} = from_excel_coords(input)
    {row - 1, col - 1}
  end

  @doc ~S"""
  Returns the ISO String representation (in UTC) for a erlang datetime() or datetime1970()
  object.

  ## Examples

      iex> iso_from_datetime {{2000, 12, 30}, {23, 59, 59}}
      "2000-12-30T23:59:59Z"

  """
  @type datetime_t :: :calendar.datetime()
  @spec iso_from_datetime(datetime_t) :: String.t()
  def iso_from_datetime(calendar) do
    {{y, m, d}, {hours, minutes, seconds}} = calendar

    to_string(
      :io_lib.format(
        '~4.10.0b-~2.10.0b-~2.10.0bT~2.10.0b:~2.10.0b:~2.10.0bZ',
        [y, m, d, hours, minutes, seconds]
      )
    )
  end

  @doc ~S"""
  Returns

  - the current current timestamp if input is nil,
  - the UNIX-Timestamp interpretation when given an integer,

  both in ISO-Repr.

  If input is a String, the string is returned:

      iex> iso_timestamp 0
      "1970-01-01T00:00:00Z"

      iex> iso_timestamp 1447885907
      "2015-11-18T22:31:47Z"

  It doesn't validate string inputs though:

      iex> iso_timestamp "goat"
      "goat"

  """
  @spec iso_timestamp(String.t() | integer | nil) :: String.t()
  def iso_timestamp(input \\ nil) do
    cond do
      input == nil ->
        iso_from_datetime(:calendar.universal_time())

      is_integer(input) ->
        iso_from_datetime(
          :calendar.now_to_universal_time({div(input, 1_000_000), rem(input, 1_000_000), 0})
        )

      # TODO this case should parse the string i guess
      # TODO also prominently absent: [char].
      XML.valid?(input) ->
        input

      true ->
        raise "Invalid input to iso_timestamp." <> inspect(input)
    end
  end

  @excel_epoch {{1899, 12, 31}, {0, 0, 0}}
  @secs_per_day 86400

  @doc ~S"""
  Convert an erlang `:calendar` object, or a unix timestamp to an excel timestamp.

  Timestampts that are already in excel format are passed through
  unmodified.
  """
  @spec to_excel_datetime(datetime_t) :: {:excelts, number}
  def to_excel_datetime({{yy, mm, dd}, {h, m, s}}) do
    in_seconds = :calendar.datetime_to_gregorian_seconds({{yy, mm, dd}, {h, m, s}})
    excel_epoch = :calendar.datetime_to_gregorian_seconds(@excel_epoch)

    t_diff = (in_seconds - excel_epoch) / @secs_per_day

    # Apply the "Lotus 123" bug - 1900 is considered a leap year.
    t_diff =
      if t_diff > 59 do
        t_diff + 1
      else
        t_diff
      end

    {:excelts, t_diff}
  end

  @spec to_excel_datetime(number) :: {:excelts, number}
  def to_excel_datetime(input) when is_number(input) do
    to_excel_datetime(
      :calendar.now_to_universal_time({div(input, 1_000_000), rem(input, 1_000_000), 0})
    )
  end

  @spec to_excel_datetime({:excelts, number}) :: {:excelts, number}
  def to_excel_datetime({:excelts, value}) do
    {:excelts, value}
  end

  # Formula's value calculate on opening excel program.
  # We don't need to format this here.
  @spec to_excel_datetime({:formula, String.t()}) :: {:formula, String.t()}
  def to_excel_datetime({:formula, value}) do
    {:formula, value}
  end

  @doc ~S"""
  Replace_all(input, [{search, replace}]).

  ## Examples

      iex> replace_all("Hello World", [{"e", "E"}, {"o", "oO"}])
      "HElloO WoOrld"

  """
  @spec replace_all(String.t(), [{String.t(), String.t()}]) :: String.t()

  def replace_all(input, [{s, r} | srx]) do
    String.replace(input, s, r) |> replace_all(srx)
  end

  def replace_all(input, []) do
    input
  end

  @version Mix.Project.config()[:version]
  @doc ~S"""
  Returns the application version suitable for the <ApplicationVersion> tag.
  """
  def app_version_string do
    String.replace(@version, ~r/(\d+)\.(\d+)\.(\d+)/, "\\1.\\2\\3")
  end

  @doc """
  The total width of the given range of columns
  """
  @spec width_from_col_range(Sheet.t(), number, number) :: number
  def width_from_col_range(_sheet, a, b) when b < a do
    0
  end

  def width_from_col_range(sheet, a, b) do
    a..b
    |> Enum.into([])
    |> Enum.uniq()
    |> Enum.map(fn i -> sheet.col_widths[i + 1] || @col_width end)
    |> Enum.sum()
  end

  @doc """
  The total height of the given range of rows
  """
  @spec height_from_row_range(Sheet.t(), number, number) :: number
  def height_from_row_range(_sheet, a, b) when b < a do
    0
  end

  def height_from_row_range(sheet, a, b) do
    a..b
    |> Enum.into([])
    |> Enum.uniq()
    |> Enum.map(fn i -> sheet.row_heights[i + 1] || @row_height end)
    |> Enum.sum()
  end

  @doc """
  Convert width to pixels
  """
  @spec width_to_px(Sheet.t(), number) :: number
  def width_to_px(_, 0) do
    0
  end

  def width_to_px(sheet, v) do
    round(v * sheet.max_char_width + @padding)
  end

  @doc """
  Convert width to emu
  """
  @spec width_to_emu(Sheet.t(), number) :: number
  def width_to_emu(sheet, v) do
    round(width_to_px(sheet, v) * sheet.emu)
  end

  @doc """
  Convert height to pixels
  """
  @spec height_to_px(number) :: number
  def height_to_px(v) do
    4 / 3 * v
  end

  @doc """
  Convert height to emu
  """
  @spec height_to_emu(Sheet.t(), number) :: number
  def height_to_emu(sheet, v) do
    round(height_to_px(v) * sheet.emu)
  end

  @doc """
  Convert pixels to width
  """
  @spec px_to_width(Sheet.t(), number) :: number
  def px_to_width(sheet, px) do
    if px <= 12 do
      px / (sheet.max_char_width + @padding)
    else
      (px - @padding) / sheet.max_char_width
    end
  end

  @doc """
  Convert pixels to height
  """
  @spec px_to_height(number) :: number
  def px_to_height(px) do
    0.75 * px
  end

  @doc """
  Figure out which columns a pixel width would span.
  """
  @spec px_to_col_span(Sheet.t(), number, number) :: {number, number, number}
  def px_to_col_span(s, start, px) do
    {end_col, remaining_px} = col_span_acc(s, px, start, 0)
    {start, end_col, remaining_px}
  end

  @spec col_span_acc(Sheet.t(), number, number, number) :: {number, number}
  defp col_span_acc(s, px, col, total) do
    w = s.col_widths[col + 1] || @col_width
    p = width_to_px(s, w)
    t = total + p

    if px > t do
      col_span_acc(s, px, col + 1, t)
    else
      cond do
        t == px ->
          {col, p}

        total == 0 ->
          {col, px}

        true ->
          {col, px - total}
      end
    end
  end

  @doc """
  Figure out which rows a pixel height would span.
  """
  @spec px_to_row_span(Sheet.t(), number, number) :: {number, number, number}
  def px_to_row_span(s, start, px) do
    {end_row, remaining_px} = row_span_acc(s, px, start, 0)
    {start, end_row, remaining_px}
  end

  @spec row_span_acc(Sheet.t(), number, number, number) :: {number, number}
  defp row_span_acc(s, px, row, total) do
    h = s.row_heights[row + 1] || @row_height
    p = height_to_px(h)
    t = total + p

    if px > t do
      row_span_acc(s, px, row + 1, t)
    else
      cond do
        t == px ->
          {row, p}

        total == 0 ->
          {row, px}

        true ->
          {row, px - total}
      end
    end
  end

  @spec px_to_emu(Sheet.t(), number) :: number
  def px_to_emu(sheet, px) do
    round(px * sheet.emu)
  end
end
