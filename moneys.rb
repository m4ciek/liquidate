#!/usr/bin/env ruby

require 'net/http'
require 'json'

Thread.abort_on_exception = true

qcx_thread = Thread.new do
	puts "starting quadrigacx [qcx]"

	quadrigacx_templ=URI "https://api.quadrigacx.com/v2/ticker?book=%s"

	(
		%w{ btc_cad eth_cad btg_cad ltc_cad }.each_with_object (
			(Net::HTTP.new quadrigacx_templ.host, quadrigacx_templ.port).tap do |http|
				puts "qcx: connecting…"
				http.use_ssl = true
				http.start
				puts "qcx: …connected"
			end
		)
	).map do |book, (http)|
		puts "qcx: #{book}"
		[ book, (http.request Net::HTTP::Get.new (format quadrigacx_templ.to_s, book)) ]
	end
end

puts "starting binance [bin]"
binance_tickers = URI 'https://api.binance.com/api/v1/ticker/allBookTickers'

iota_in_btc = Rational (
	(
		JSON.parse (
			(Net::HTTP.new binance_tickers.host, binance_tickers.port).tap do |http|
				puts "bin: connecting…"
				http.use_ssl = true
				http.start
				puts "bin: …connected"
			end.request Net::HTTP::Get.new binance_tickers
		).read_body
	).find do |syms|
		"IOTABTC" == (syms.fetch "symbol")
	end.fetch "bidPrice"
)

printf "bin: MIOTA is worth %f BTC\n", iota_in_btc

puts "bin: done. waiting to parse quadrigacx… (qcx_thread status: #{qcx_thread.status})"

qcx_tickers = qcx_thread.value.tap do
	puts "qcx: done\n"
end.map do |book, ticker_vals|
	hilolt = ((JSON.parse ticker_vals.read_body).values_at "high","low","last").map &:to_r
	puts "#{book} high/low/last: " + ((hilolt.map &:to_f).join ", ")
	[ book, hilolt ]
end

btc_cad, eth_cad, btg_cad, ltc_cad = qcx_tickers.map &:last

costs_to_date = ARGV[0..-6].reduce 0 do |s,c| s += c.to_r end
iota_held, btg_held, btc_held, eth_held, ltc_held = (-5..-1).map do |idx| Rational ARGV[idx], 100000000 end

holdings_in_cad = btc_cad.last * btc_held +
	eth_cad.last * eth_held +
	btg_cad.last * btg_held +
	ltc_cad.last * ltc_held +
	btc_cad.last * iota_held * iota_in_btc

printf "done!\n\nOkay, here's how it looksⓇ:\n\n\t* you have CAD $%s held in total\n\t\t* btc:\t$%s\n\t\t* eth:\t$%s\n\t\t* btg:\t$%s\n\t\t* iota:\t$%s\n\t\t* ltc:\t$%s\n\t* less costs of $%s…\n\t* …makes $%s earned to date\n\t* return as a percentage is %s%%.\n\nGreat Work™\n\n\n",
	((holdings_in_cad*100000).to_i.to_s.insert -6,"."),
	((format "%06i", btc_cad.last*btc_held*100000).insert -6,"."),
	((format "%06i",(eth_cad.last*eth_held*100000).to_i).insert -6,"."),
	((btg_cad.last*btg_held*100000).to_i.to_s.insert -6,"."),
	((format "%06i", btc_cad.last*iota_held*iota_in_btc*100000).insert -6,"."),
	((ltc_cad.last*ltc_held*100000).to_i.to_s.insert -6,"."),
	((costs_to_date*100000).to_i.to_s.insert -6,"."),
	(((holdings_in_cad-costs_to_date)*100000).to_i.to_s.insert -6,"."),
	((10000*(holdings_in_cad - costs_to_date)/costs_to_date).to_i.to_s.insert -3,".")
