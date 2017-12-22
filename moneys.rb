#!/usr/bin/env ruby

require 'net/http'
require 'json'

Thread.abort_on_exception = true

cx_q = Queue.new

cx_list = [
	[ "quadrigacx", "qcx", "https://api.quadrigacx.com/v2/ticker?book=%s",
		%w{ btc_cad eth_cad btg_cad ltc_cad bch_cad },
		->(api_res) do
			api_res.values_at "high","low","last"
		end
	],

# for future development — check "success" and "message" keys in response
# expected:
# {"success":true,"message":"","result":{"Bid":0.00001184,"Ask":0.00001185,"Last":0.00001185}}

	[ "bittrex", "btx", "https://bittrex.com/api/v1.1/public/getticker?market=%s",
		%w{ BTC-ADA BTC-DOGE },
		->(api_res) do
			(api_res.fetch "result").values_at "Bid", "Ask", "Last"
		end
	],

# binance might have a method that returns the ticker for just one book…
	[ "binance", "bin", "https://api.binance.com/api/v1/ticker/allBookTickers",
   		%w{ IOTABTC },
		->(api_res) do
			api_res.find do |syms|
				"IOTABTC" == (syms.fetch "symbol")
			end.values_at "bidPrice", "askPrice"
		end
	]
]
	
cx_list.each do |t_args|
	cx_thr = Thread.new *t_args[0...-1] do |cx_long, cx, uri_templ_str, tickrs|
		uri_templ = URI uri_templ_str

		http = (Net::HTTP.new uri_templ.host, uri_templ.port).tap do |http|
			http.use_ssl = uri_templ.scheme == 'https'
			http.start
		end

		# improvement: don't wait for all to be finished; instead, return piecemeal in a Queue
		# (that's a pretty major redesign overall since we'd no longer wait for threads to
		# complete. We'd be more interested in waiting for data, since that's what we really
		# care about, anyway.)
		tickrs.map do |book|
			[ book, (http.request Net::HTTP::Get.new format uri_templ_str, book) ]
		end.tap do
			cx_q.enq [ (Process.clock_gettime Process::CLOCK_MONOTONIC), Thread.current ]
		end
	end

	cx_thr.name = t_args[1]
	cx_thr.thread_variable_set :parser, t_args.last
	cx_thr.thread_variable_set :long_name, t_args.first
end

on_your_marks = Process.clock_gettime Process::CLOCK_MONOTONIC

tickers = cx_list.size.times.map do |idx|
	thr_delay, thr = cx_q.deq

	t_now = Process.clock_gettime Process::CLOCK_MONOTONIC

	printf "%s: %s has arrived! order: %i of %i; interactive wait time: %f s; time languishing in queue: %f µs\n",
		thr.name, (thr.thread_variable_get :long_name), idx.succ, cx_list.size,
		(t_now - on_your_marks), (t_now - thr_delay) * 1000000

	[
		thr.name,
		thr.value.map do |book, ticker_vals|
			hilolt = (thr.thread_variable_get :parser)[
				JSON.parse ticker_vals.read_body
			].map &:to_r

			# XXX this output is crappy. Perhaps it should differ per-currency. Whatever…
			puts "\t#{book}: " + ((hilolt.map &:to_f).join ", ")
			[ book, hilolt ]
		end
	]
end

btc_cad, eth_cad, btg_cad, ltc_cad, bch_cad = (tickers.assoc "qcx").last.map &:last
ada_btc, = (tickers.assoc "btx").last.map &:last
iota_btc = ((tickers.assoc "bin").last.assoc "IOTABTC").last

cad_cad = [ 1, 1, 1 ]

costs_to_date = ARGV[0..-9].reduce 0 do |s,c| s += c.to_r end

cad_held, iota_held, btg_held, btc_held, eth_held, ltc_held, bch_held, ada_held =
	(-8..-1).map do |idx|
		Rational ARGV[idx], 100000000
	end

holdings_in_cad =
	cad_held +
	btc_cad.last * btc_held +
	eth_cad.last * eth_held +
	btg_cad.last * btg_held +
	ltc_cad.last * ltc_held +
	bch_cad.last * bch_held +
	btc_cad.last * iota_held * iota_btc.last +
	btc_cad.last * ada_held * ada_btc.last

puts (
	"\nOkay, here's how it looksⓇ:\n\n" +
	"\t* you have CAD $%i.%02i held in total\n" +
		(%w{ cad btc eth btg iota ltc bch ada }.map do |tck| 
			"\t\t* #{tck}:\t$%i.%02i\n"
		end.join) +
	"\t* less costs of $%i.%02i…\n" +
	"\t* …makes $%i.%02i earned to date\n" +
	"\t* return as a percentage is %02i.%01i%%.\n" +
	"\nGreat Work™\n\n"
) % (
	(
		[
			holdings_in_cad,
			cad_cad.last * cad_held,
			btc_cad.last * btc_held,
			eth_cad.last * eth_held,
			btg_cad.last * btg_held,
			btc_cad.last * iota_held * iota_btc.last,
			ltc_cad.last * ltc_held,
			bch_cad.last * bch_held,
			btc_cad.last * ada_held * ada_btc.last,
			costs_to_date,
			holdings_in_cad - costs_to_date
		].flat_map do |amt|
			(amt * 1000).divmod 1000
		end
	) + (
		( 100000 * (holdings_in_cad - costs_to_date) /
			 costs_to_date ).divmod 1000
	)
)
