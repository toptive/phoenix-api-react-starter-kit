defmodule StarterKitWeb.Serializers.ApiErrorBodySerializer do
  @moduledoc "The translated API error body."
  use Typelizer.Serializer
  attribute :code, type: :string
  attribute :message, type: :string
  attribute :details, type: :map
end

defmodule StarterKitWeb.Serializers.FieldErrorSerializer do
  @moduledoc "A translated validation error and its optional interpolation bindings."
  use Typelizer.Serializer
  attribute :key, type: :string
  attribute :message, type: :string
  attribute :bindings, type: {:map, {:union, [:string, :number]}}, optional: true
end

defmodule StarterKitWeb.Serializers.ApiEnvelopeSerializer do
  @moduledoc "Declares the generic success envelope for generated transport types."
  use Typelizer.Serializer
  attribute :response, type: {:envelope, :unknown}
end
