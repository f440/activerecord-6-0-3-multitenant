# frozen_string_literal: true

require "bundler/inline"

gemfile(true) do
  source "https://rubygems.org"

  git_source(:github) { |repo| "https://github.com/#{repo}.git" }

  # Activate the gem you are reporting the issue against.
  gem "rails", ENV["RAILS_VERSION"] || "6.0.3"
  gem "sqlite3"
  gem "activerecord-multi-tenant", require: false
end

require "active_record/railtie"
require "active_storage/engine"
require "tmpdir"
require "activerecord-multi-tenant"

class TestApp < Rails::Application
  config.root = __dir__
  config.hosts << "example.org"
  config.eager_load = false
  config.session_store :cookie_store, key: "cookie_store_key"
  secrets.secret_key_base = "secret_key_base"

  config.logger = Logger.new($stdout)
  Rails.logger  = config.logger

  config.active_storage.service = :local
  config.active_storage.service_configurations = {
    local: {
      root: Dir.tmpdir,
      service: "Disk"
    }
  }
end

ENV["DATABASE_URL"] = "sqlite3::memory:"

Rails.application.initialize!

require ActiveStorage::Engine.root.join("db/migrate/20170806125915_create_active_storage_tables.rb").to_s

ActiveRecord::Schema.define do
  CreateActiveStorageTables.new.change

  create_table :tenants
  create_table :groups, force: true do |t|
    t.integer :tenant_id, null: false
  end
  create_table :users, force: true do |t|
    t.integer :tenant_id, null: false
    t.integer :group_id, null: false
  end
end

class Tenant < ActiveRecord::Base
end

class Group < ActiveRecord::Base
  multi_tenant :tenant
  has_many :users
end

class User < ActiveRecord::Base
  multi_tenant :tenant
  belongs_to :group

  has_one_attached :profile
end

require "minitest/autorun"

class BugTest < Minitest::Test
  def test_join
    tenant = Tenant.create!
    group = Group.create!(tenant: tenant)

    User.create!(
      tenant: tenant,
      group: group,
      profile: {
        content_type: "text/plain",
        filename: "dummy.txt",
        io: ::StringIO.new("dummy"),
      }
    )

    assert_equal group.id, Group.joins(users: { profile_attachment: :blob }).find(group.id).id
  end
end
