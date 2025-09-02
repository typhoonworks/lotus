# MySQL-specific type normalizers
# Only compiled when MyXQL types are available

if Code.ensure_loaded?(MyXQL.Geometry) do
  defimpl Lotus.Export.Normalizer, for: MyXQL.Geometry do
    def normalize(%MyXQL.Geometry{} = geom) do
      # Export as WKT (Well-Known Text) or WKB Base64
      Base.encode64(geom.wkb || "")
    end
  end
end

# Handle MySQL zero dates
if Code.ensure_loaded?(MyXQL) do
  # MyXQL returns these as strings already, but we can add special handling if needed
  # "0000-00-00" dates are typically returned as nil or strings by MyXQL
end
