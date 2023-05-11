defmodule AR do
  @moduledoc """
  Documentation for `AR`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> AR.hello()
      :world

  """
  require Wallaby.Browser
  import Wallaby.Browser
  alias Wallaby.{Browser, Query, Element}

  def check_env() do
    {Application.get_env(:amazon_refunds, :username), Application.get_env(:amazon_refunds, :password)}
  end

  def get_order_summary() do
    IO.puts("Downloading transactions")
    {:ok, session} = Wallaby.start_session()

    session = session
    |> Browser.visit("http://www.amazon.com")
    |> Browser.click(Query.css(".nav-line-1-container"))
    |> Browser.fill_in(Query.css("input[type='email']"), with: Application.get_env(:amazon_refunds, :username))
    |> Browser.click(Query.css("span#continue"))
    |> Browser.fill_in(Query.css("input[type='password']"), with: Application.get_env(:amazon_refunds, :password))
    |> Browser.click(Query.css("input#signInSubmit"))
    |> Browser.visit("https://www.amazon.com/cpe/yourpayments/transactions")

    {%{} = order_summary, %MapSet{} = links} = transaction_summary(session, %{}, MapSet.new(), Date.from_erl!({2023, 1, 1}))
    IO.puts("#{length(Map.keys(order_summary))} should equal #{MapSet.size(links)}")
    alternate_order_summary = summarize_orders(session, links)

    non_matching_orders = Enum.filter(order_summary, fn {order_number, totals} ->
      alternate_totals = Map.get(alternate_order_summary, order_number)
      alternate_totals[:credits] != totals[:credits] || alternate_totals[:debits] != totals[:debits]
    end)
    |> IO.inspect(label: "Non matching orders(transactions)")

    # non_matching_order_numbers = Enum.map(non_matching_orders, fn {order_number, _totals} -> order_number end) |> MapSet.new()
    # non_matching_orders_two = Enum.filter(alternate_order_summary, fn {order_number, _totals} -> MapSet.member?(non_matching_order_numbers, order_number) end)
    # |> IO.inspect(label: "Non matching orders(order details)")


    # {non_matching_orders, non_matching_orders_two}
  end

  defp summarize_orders(session, links) do
    Enum.reduce(links, %{}, fn link, acc ->
      order_number = Browser.visit(session, link)
      |> Browser.text(Query.css(".order-date-invoice-item bdi"))
      |> IO.inspect(label: "Order number")

      debit_total = Browser.text(session, Query.xpath("//div[@id='od-subtotals']//span[contains(text(), 'Grand Total')]/../following-sibling::div"))
      |> String.slice(1..-1) |> String.to_float()

      credit_total = cond do
        my_has?(session, Query.css("#od-subtotals a span.a-color-success", text: "Refund Total")) ->
          Browser.text(session, Query.xpath("//div[@id='od-subtotals']//a//span[contains(text(), 'Refund Total')]/../../../../following-sibling::div"))
          |> String.slice(1..-1)
          |> String.to_float()
        true -> 0.0
      end

      Map.put(acc, order_number, %{credits: credit_total, debits: debit_total})
    end)
  end

  @doc """
  session: wallaby browser session that controls the browser
  order_summary: tracks total credits/debits per order, keyed by order number
  links: unique set of links to all associated orders
  through_date: the date at which the function will stop gathering transactions
  """
  defp transaction_summary(session, order_summary, links, through_date) do
    dates = Browser.all(session, Query.css(".apx-transaction-date-container"))
    date_str = Element.text(Enum.at(dates, 0))
    date = parse_date(date_str)
    IO.inspect(date, label: "Date")
    case Date.compare(date, through_date) do
      :lt -> {order_summary, links}
      :gt ->
        transactions = Browser.all(session, Query.css(".apx-transactions-line-item-component-container"))
        {new_order_summary, new_links} = Enum.reduce(transactions, {order_summary, links}, fn transaction, {order_summary_acc, links_acc} ->
          query = Query.css("a")
          if Browser.has?(transaction, query) do
            order_link = Browser.find(transaction, query)
            href = Element.attr(order_link, "href")
            order_number_text = Element.text(order_link)
            regex = ~r/Order #(?<order_number>\d{3}-\d{7}-\d{7})/
            captures = Regex.named_captures(regex, order_number_text)
            if captures do
              links_acc = MapSet.put(links_acc, href)
              order_number = captures["order_number"]
              order_summary_acc = Map.put_new(order_summary_acc, order_number, %{credits: 0, debits: 0})

              bolded = Browser.all(transaction, Query.css(".a-text-bold"))
              amount = Enum.at(bolded, 1) |> Element.text()
              type = if String.starts_with?(amount, "-"), do: :debits, else: :credits
              dollar_amount = String.slice(amount, 2..-1) |> String.replace(",", "") |> String.to_float()

              if order_number == "114-0806350-2475431" do
                IO.puts("#{order_number} #{amount}")
              end

              {update_in(order_summary_acc, [order_number, type], &(&1 + dollar_amount)), links_acc}
            else
              {order_summary_acc, links_acc}
            end
          else
            {order_summary_acc, links_acc}
          end
        end)


        Browser.find(session, Query.css(".a-button-inner", text: "Next Page"))
        |> Browser.click(Query.css("input"))

        my_refute_has(session, Query.css(".apx-transaction-date-container", text: date_str))

        transaction_summary(session, new_order_summary, new_links, through_date)
    end
  end

  @months %{
    "January" => 1,
    "February" => 2,
    "March" => 3,
    "April" => 4,
    "May" => 5,
    "June" => 6,
    "July" => 7,
    "August" => 8,
    "September" => 9,
    "October" => 10,
    "November" => 11,
    "December" => 12
  }

  defp parse_date(date_str) do
    [month_str, day_str, year_str] = String.split(date_str, " ")

    month = @months[month_str]
    day = String.replace(day_str, ",", "") |> String.to_integer()
    year = String.to_integer(year_str)

    Date.new!(year, month, day)
  end

  @max_wait_time 3_000

  def my_refute_has(session, query, start_time \\ current_time()) do
    case my_execute_query(session, query) do
      {:ok, %{result: result} = query_result} ->
        case length(result) do
          0 ->
            session
          _ ->
            if max_time_exceeded?(start_time) do
              raise Wallaby.ExpectationNotMetError,
                    Query.ErrorMessage.message(query_result, :found)
            else
              my_refute_has(session, query, start_time)
            end
        end
    end
  end

  def my_has?(session, query) do
    case my_execute_query(session, query) do
      {:ok, %{result: result} = query_result} ->
        case length(result) do
          0 -> false
          _ -> true
        end
    end
  end

  def my_execute_query(%{driver: driver} = parent, query) do
    try do
      with {:ok, query} <- Query.validate(query),
            compiled_query <- Query.compile(query),
            {:ok, elements} <- driver.find_elements(parent, compiled_query),
            {:ok, elements} <- validate_text(query, elements) do
        {:ok, %Query{query | result: elements}}
      end
    rescue
      StaleReferenceError ->
        {:error, :stale_reference}
    end
  end

  defp validate_text(query, elements) do
    text = Query.inner_text(query)

    if text do
      {:ok, Enum.filter(elements, &matching_text?(&1, text))}
    else
      {:ok, elements}
    end
  end

  defp matching_text?(%Element{driver: driver} = element, text) do
    case driver.text(element) do
      {:ok, element_text} ->
        element_text =~ ~r/#{Regex.escape(text)}/

      {:error, _} ->
        false
    end
  end

  defp current_time do
    :erlang.monotonic_time(:milli_seconds)
  end

  defp max_time_exceeded?(start_time) do
    current_time() - start_time > @max_wait_time
  end
end
