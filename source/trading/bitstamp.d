module trading.bitstamp;

import vibe.d;

static struct BS
{
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
	Json orderStatus(string id);
	///
	Json transactions(string pair);
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
	Json orderStatus(string id)
	{
		static immutable METHOD_URL = "/order_status/";

		string[string] params;
		params["id"] = id;

		return request!Json(METHOD_URL, params);
	}

	///
	Json transactions(string pair)
	{
		static immutable METHOD_URL = "/v2/user_transactions/";

		string[string] params;
		params["limit"] = "1000";

		return request!Json(METHOD_URL ~ pair ~ "/", params);
	}

	///
	Json buyMarket(string pair, float amount)
	{
		static immutable METHOD_URL = "/v2/buy/market/";

		string[string] params;
		params["amount"] = to!string(amount);

		return request!Json(METHOD_URL ~ pair ~ "/", params);
	}

	///
	Json sellMarket(string pair, float amount)
	{
		static immutable METHOD_URL = "/v2/sell/market/";

		string[string] params;
		params["amount"] = to!string(amount);

		return request!Json(METHOD_URL ~ pair ~ "/", params);
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

			//logInfo("Response: %s", json);

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
