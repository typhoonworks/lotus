defmodule Lotus.AI.ErrorTest do
  use ExUnit.Case, async: true

  alias Lotus.AI.Error
  alias ReqLLM.Error.API.Request, as: APIRequest

  describe "wrap/1" do
    test "wraps 429 status as RateLimitError" do
      raw = APIRequest.exception(status: 429, reason: "Too many requests")
      assert %Error.RateLimitError{} = Error.wrap(raw)
    end

    test "wraps 401 status as AuthenticationError" do
      raw = APIRequest.exception(status: 401, reason: "Unauthorized")
      assert %Error.AuthenticationError{} = Error.wrap(raw)
    end

    test "wraps 403 status as AuthenticationError" do
      raw = APIRequest.exception(status: 403, reason: "Forbidden")
      assert %Error.AuthenticationError{} = Error.wrap(raw)
    end

    test "wraps 5xx status as ServerError" do
      raw = APIRequest.exception(status: 500, reason: "Internal Server Error")
      assert %Error.ServerError{} = Error.wrap(raw)

      raw = APIRequest.exception(status: 503, reason: "Service Unavailable")
      assert %Error.ServerError{} = Error.wrap(raw)
    end

    test "wraps timeout reason as TimeoutError" do
      raw = APIRequest.exception(status: nil, reason: "request timed out")
      assert %Error.TimeoutError{} = Error.wrap(raw)

      raw = APIRequest.exception(status: nil, reason: "timeout")
      assert %Error.TimeoutError{} = Error.wrap(raw)
    end

    test "wraps other API request errors as ServiceError" do
      raw = APIRequest.exception(status: 400, reason: "Bad Request")
      assert %Error.ServiceError{} = Error.wrap(raw)
    end

    test "wraps unknown error terms as ServiceError" do
      assert %Error.ServiceError{} = Error.wrap(:something_unexpected)
      assert %Error.ServiceError{} = Error.wrap("string error")
      assert %Error.ServiceError{} = Error.wrap(%RuntimeError{message: "boom"})
    end

    test "all error structs implement Exception with user-friendly messages" do
      assert Exception.message(%Error.RateLimitError{}) =~ "rate limits"
      assert Exception.message(%Error.AuthenticationError{}) =~ "authentication"
      assert Exception.message(%Error.ServerError{}) =~ "temporarily unavailable"
      assert Exception.message(%Error.TimeoutError{}) =~ "timed out"
      assert Exception.message(%Error.ServiceError{}) =~ "unexpected error"
    end
  end
end
