class CreateRequests < ActiveRecord::Migration[5.2]
  def change
    create_table :requests do |t|
      t.string :original_urk
      t.string :query_params
      t.string :errors
      t.timestamps
    end
  end
end
