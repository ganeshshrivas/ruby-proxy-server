class CreateRequests < ActiveRecord::Migration[5.2]
  def change
    create_table :requests do |t|
      t.string :original_url
      t.string :query_params
      t.string :req_errors
      t.timestamps
    end
  end
end
