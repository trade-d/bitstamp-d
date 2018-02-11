module trading.bitstamp;

import vibe.d;

static struct BS
{
	///
	struct TickerResult
	{
		string timestamp;
		string last;
		string open;
		string volume;
		string low;
		string vwap;
		string high;
		string ask;
		string bid;
	}

	///
	struct OrderStatus 
	{
		///
		struct Transaction
		{
			///
			string xrp;
			///
			string price;
			///
			string fee;
			///
			int type;
			///
			int tid;
			///
			string usd;
			///
			string datetime;
		}

		/// 
		string status;
		///
		Transaction[] transactions;

		///
		bool isStatusFinished() const { return this.status == "Finished"; }
		///
		bool isStatusOpen() const { return this.status == "Open"; }
		///
		bool isStatusInQueue() const { return this.status == "In Queue"; }
	}

	///
	struct Transaction
	{
		///
		float xrp_usd;
		///
		float btc;
		///
		string xrp;
		///
		float eur;
		///
		string fee;
		///
		string type;
		///
		int order_id;
		///
		string usd;
		///
		int id;
		///
		string datetime;
	}

	alias Transactions = Transaction[];

	///
	struct Order
	{
		///
		string price;
		///
		string amount;
		///
		string type;
		///
		string datetime;
		///
		string id;
	}

	///
	struct Balance 
	{
		@optional string xrp_balance;
		@optional string xrp_reserved;
		@optional string xrp_available;

		@optional string usd_balance;
		@optional string usd_reserved;
		@optional string usd_available;

		@optional string eur_balance;
		@optional string eur_reserved;
		@optional string eur_available;
		
		@optional string btc_balance;
		@optional string btc_reserved;
		@optional string btc_available;

		float fee;
	}
}

///
@path("/v2/")
interface BitstampPublicAPI
{
	///
	@method(HTTPMethod.GET)
	@path("ticker/:pair")
	BS.TickerResult ticker(string _pair);
}

///
@path("/v2/")
interface BitstampPrivateAPI
{
	///
	BS.OrderStatus orderStatus(int order_id);
	///
	BS.Transactions transactions(string pair);
	///
	BS.Order sellMarket(string pair, float amount);
	///
	BS.Order buyMarket(string pair, float amount);
	///
	BS.Balance balance(string pair);
}

///
final class Bitstamp : BitstampPublicAPI, BitstampPrivateAPI
{
	private static immutable API_URL = "https://www.bitstamp.net/api";

	private string customerId;
	private string key;
	private string secret;

	private BitstampPublicAPI publicApi;

	///
	this(string customerId, string key, string secret)
	{
		this.customerId = customerId;
		this.key = key;
		this.secret = secret;
		this.publicApi = new RestInterfaceClient!BitstampPublicAPI(API_URL);
	}

	///
	BS.TickerResult ticker(string pair)
	{
		return publicApi.ticker(pair);
	}

	unittest
	{
		auto api = new Bitstamp("", "", "");
		auto res = api.ticker("xrpusd");
		assert(res.last != "");
	}

	///
	BS.OrderStatus orderStatus(int order_id)
	{
		static immutable METHOD_URL = "/order_status/";

		string[string] params;
		params["id"] = to!string(order_id);

		return request!(BS.OrderStatus)(METHOD_URL, params);
	}

	///
	BS.Transactions transactions(string pair)
	{
		static immutable METHOD_URL = "/v2/user_transactions/";

		string[string] params;
		params["limit"] = "1000";

		return request!(BS.Transactions)(METHOD_URL ~ pair ~ "/", params);
	}

	///
	BS.Order buyMarket(string pair, float amount)
	{
		static immutable METHOD_URL = "/v2/buy/market/";

		string[string] params;
		params["amount"] = to!string(amount);

		return request!(BS.Order)(METHOD_URL ~ pair ~ "/", params);
	}

	///
	BS.Order sellMarket(string pair, float amount)
	{
		static immutable METHOD_URL = "/v2/sell/market/";

		string[string] params;
		params["amount"] = to!string(amount);

		return request!(BS.Order)(METHOD_URL ~ pair ~ "/", params);
	}

	///
	BS.Balance balance(string pair)
	{
		static immutable METHOD_URL = "/v2/balance/";

		string[string] params;

		return request!(BS.Balance)(METHOD_URL ~ pair ~ "/", params);
	}

	private auto request(T)(string path, string[string] params)
	{
		import std.digest.sha : SHA256, toHexString, LetterCase;
		import std.conv : to;
		import std.digest.hmac : hmac;
		import std.string : representation;
		import std.array : Appender;

		auto res = requestHTTP(API_URL ~ path, (scope HTTPClientRequest req) {

			string nonce = Clock.currStdTime().to!string;
			string payload = nonce ~ this.customerId ~ this.key;

			string signature = payload.representation.hmac!SHA256(secret.representation)
				.toHexString!(LetterCase.upper).idup;

			params["nonce"] = nonce;
			params["key"] = this.key;
			params["signature"] = signature;

			Appender!string app;
			app.formEncode(params);

			string bodyData = app.data;

			req.method = HTTPMethod.POST;
			req.headers["Content-Type"] = "application/x-www-form-urlencoded";
			req.headers["Content-Length"] = (app.data.length).to!string;

			req.bodyWriter.write(app.data);
		});
		scope (exit)
		{
			res.dropBody();
		}

		if (res.statusCode == 200)
		{
			auto json = res.readJson();

			scope(failure)
			{
				logError("Response deserialize failed: %s", json);
			}

			return deserializeJson!T(json);
		}
		else
		{
			logDebug("API Error: %s", res.bodyReader.readAllUTF8());
			logError("API Error Code: %s", res.statusCode);
			throw new Exception("API Error");
		}
	}
}
