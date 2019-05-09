class Request < ApplicationRecord
 serialize :query_params, Hash
 serialize :error, Hash


end
