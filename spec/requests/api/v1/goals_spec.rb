# frozen_string_literal: true

require "swagger_helper"

money = ->(description) { { type: :string, nullable: true, description: description } }
cents = { type: :integer, nullable: true }

goal_pledge_schema = {
  type: :object,
  required: %w[id account_id kind status amount amount_cents currency days_left expires_at created_at],
  properties: {
    id: { type: :string, format: :uuid },
    account_id: { type: :string, format: :uuid },
    account_name: { type: :string, nullable: true, description: "Null when the caller cannot access the account" },
    kind: { type: :string, enum: %w[transfer manual_save] },
    status: { type: :string, enum: %w[open matched cancelled expired] },
    amount: { type: :string },
    amount_cents: { type: :integer },
    currency: { type: :string },
    days_left: { type: :integer },
    expires_at: { type: :string, format: "date-time" },
    created_at: { type: :string, format: "date-time" }
  }
}.freeze

goal_schema = {
  type: :object,
  required: %w[id name kind target_mode state status display_status currency target_amount target_amount_cents
               current_amount_cents progress_amount_cents remaining_amount_cents progress_percent
               open_pledges linked_accounts linked_account_count],
  properties: {
    id: { type: :string, format: :uuid },
    name: { type: :string },
    kind: { type: :string, enum: %w[one_off maintained] },
    target_mode: { type: :string, enum: %w[fixed months_of_expenses] },
    target_months: { type: :integer, nullable: true },
    state: { type: :string, enum: %w[active paused completed archived] },
    status: { type: :string, enum: %w[reached on_track behind no_target_date funded depleted] },
    display_status: { type: :string, description: "status, or the lifecycle state when paused, completed or archived" },
    color: { type: :string, nullable: true },
    icon: { type: :string, nullable: true },
    notes: { type: :string, nullable: true },
    currency: { type: :string },
    target_date: { type: :string, format: :date, nullable: true },
    days_left: { type: :integer, nullable: true },
    months_remaining: { type: :number, nullable: true },
    target_amount: money.call("Target"), target_amount_cents: cents,
    current_amount: money.call("Balance the linked accounts hold for the goal"), current_amount_cents: cents,
    progress_amount: money.call("current_amount plus consumed_amount; what the ring is drawn from"), progress_amount_cents: cents,
    consumed_amount: money.call("Already spent on the goal"), consumed_amount_cents: cents,
    remaining_amount: money.call("Still to save"), remaining_amount_cents: cents,
    monthly_target_amount: money.call("Needed per month to hit target_date; null without a date"), monthly_target_amount_cents: cents,
    pace: money.call("Average monthly net inflow over 90 days"), pace_cents: cents,
    catch_up_amount: money.call("Extra per month needed beyond pace and open pledges"), catch_up_amount_cents: cents,
    projection_end_amount: money.call("Projected balance at target_date at the current pace"), projection_end_amount_cents: cents,
    market_value: money.call("Market value of the backing"), market_value_cents: cents,
    progress_percent: { type: :integer },
    progress_basis: { type: :string, enum: %w[balance contributions] },
    months_of_runway: { type: :number, nullable: true },
    projected_completion_date: { type: :string, format: :date, nullable: true },
    available_actions: {
      type: :array,
      items: { type: :string, enum: %w[pause resume complete archive unarchive reopen consume] },
      description: "Lifecycle actions valid in the goal's current state, plus consume when the caller can record a spend"
    },
    behind_pace: { type: :boolean },
    needs_attention: { type: :boolean },
    status_callout: { type: :string, nullable: true, description: "Localized one-line status, as on the web goal page" },
    currency_conversion_incomplete: { type: :boolean },
    last_matched_pledge_date: { type: :string, format: :date, nullable: true },
    pledges_use_transfer: { type: :boolean },
    pending_pledges_count: { type: :integer },
    open_pledges: { type: :array, items: goal_pledge_schema },
    linked_account_count: { type: :integer, description: "All linked accounts, including ones the caller cannot see" },
    linked_accounts: {
      type: :array,
      description: "Linked accounts the caller can access",
      items: {
        type: :object,
        required: %w[id name accountable_type currency whole_account],
        properties: {
          id: { type: :string, format: :uuid },
          name: { type: :string },
          accountable_type: { type: :string },
          currency: { type: :string },
          whole_account: { type: :boolean },
          allocated_amount: money.call("Earmark in account currency; null for a whole-account link"),
          allocated_amount_cents: cents,
          backing_amount: money.call("This account's share of the goal, in goal currency"),
          backing_amount_cents: cents
        }
      }
    },
    completed_at: { type: :string, format: "date-time", nullable: true },
    created_at: { type: :string, format: "date-time" },
    updated_at: { type: :string, format: "date-time" }
  }
}.freeze

pledge_response_schema = {
  type: :object,
  required: %w[pledge goal],
  properties: { pledge: goal_pledge_schema, goal: goal_schema }
}.freeze

goal_input_schema = {
  type: :object,
  properties: {
    goal: {
      type: :object,
      properties: {
        name: { type: :string },
        target_amount: { type: :number },
        target_date: { type: :string, format: :date, nullable: true },
        color: { type: :string, description: "Hex color, e.g. #4da568" },
        icon: { type: :string, nullable: true },
        notes: { type: :string, nullable: true },
        kind: { type: :string, enum: %w[one_off maintained] },
        target_mode: { type: :string, enum: %w[fixed months_of_expenses] },
        target_months: { type: :integer, nullable: true },
        account_ids: { type: :array, items: { type: :string, format: :uuid },
                       description: "Depository, investment or crypto accounts the caller can access. On update, replaces the caller's visible links; links to accounts the caller cannot see are kept." },
        allocations: { type: :object, additionalProperties: { type: :string, nullable: true },
                       description: "account_id => earmark amount. Blank or missing claims the whole balance." }
      }
    }
  }
}.freeze

RSpec.describe "API V1 Goals", type: :request do
  let(:family) { Family.create!(name: "API Family", currency: "USD", locale: "en", date_format: "%m-%d-%Y") }
  let(:user) do
    family.users.create!(
      email: "goals-api@example.com", password: "password123", password_confirmation: "password123",
      preferences: { "preview_features_enabled" => true }
    )
  end
  let(:api_key) do
    ApiKey.create!(user: user, name: "API Docs Key", key: ApiKey.generate_secure_key, scopes: %w[read_write], source: "web")
  end
  let(:"X-Api-Key") { api_key.plain_key }
  let(:account) do
    Account.create!(family: family, owner: user, name: "Savings", balance: 2000, currency: "USD", accountable: Depository.create!)
  end
  let!(:goal) do
    g = family.goals.new(name: "Trip", target_amount: 5000, currency: "USD", target_date: 6.months.from_now.to_date, color: "#4da568")
    g.goal_accounts.build(account: account)
    g.save!
    g
  end

  path "/api/v1/goals" do
    get "List goals" do
      tags "Goals"
      description "All family goals with the progress figures the web goal card shows. Active goals first (needing attention first), then completed, then archived. Requires preview features."
      security [ { apiKeyAuth: [] } ]
      produces "application/json"
      parameter name: :state, in: :query, required: false, schema: { type: :string, enum: %w[active paused completed archived] }

      response "200", "goals listed" do
        schema type: :object, required: %w[goals], properties: { goals: { type: :array, items: goal_schema } }
        run_test!
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:"X-Api-Key") { nil }
        run_test!
      end

      response "403", "preview features disabled" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        before { user.update!(preferences: { "preview_features_enabled" => false }) }
        run_test!
      end

      response "422", "invalid state filter" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:state) { "bogus" }
        run_test!
      end
    end

    post "Create goal" do
      tags "Goals"
      security [ { apiKeyAuth: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, required: true, schema: goal_input_schema

      let(:other_account) do
        Account.create!(family: family, owner: user, name: "Brokerage", balance: 500, currency: "USD", accountable: Depository.create!)
      end

      response "201", "goal created" do
        schema goal_schema
        let(:body) { { goal: { name: "Bike", target_amount: 1200, account_ids: [ other_account.id ] } } }
        run_test!
      end

      response "403", "read_write scope required" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:api_key) do
          ApiKey.create!(user: user, name: "Read Key", key: ApiKey.generate_secure_key, scopes: %w[read], source: "web")
        end
        let(:body) { { goal: { name: "Bike", target_amount: 1200, account_ids: [ other_account.id ] } } }
        run_test!
      end

      response "422", "validation failed" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:body) { { goal: { name: "", target_amount: 0, account_ids: [] } } }
        run_test!
      end
    end
  end

  path "/api/v1/goals/summary" do
    get "Goals summary" do
      tags "Goals"
      description "The figures the web goals index shows in its KPI header, over active and paused goals (completed and " \
                  "archived are left out), plus the Plan hub's saved and target totals. velocity_* is the net inflow into " \
                  "goal-linked accounts over the last 30 days and the 30 days before, signed. on_track_count is out of " \
                  "tracked_total, which leaves out paused, reached, reserve and no-target-date goals. saved and target only " \
                  "include goals in the family currency."
      security [ { apiKeyAuth: [] } ]
      produces "application/json"

      response "200", "summary" do
        schema type: :object,
               required: %w[currency velocity_30d velocity_30d_cents needs_this_month needs_this_month_cents on_track_count
                            tracked_total active_total saved saved_cents target target_cents],
               properties: {
                 currency: { type: :string },
                 velocity_30d: money.call("Contributed in the last 30 days (net inflow; negative for a net outflow)"),
                 velocity_30d_cents: cents,
                 velocity_prior_30d: money.call("The same figure for the 30 days before"),
                 velocity_prior_30d_cents: cents,
                 velocity_delta_percent: { type: :number, nullable: true, description: "Change against the prior 30 days; null when that was zero" },
                 velocity_direction: { type: :string, enum: %w[up down flat] },
                 needs_this_month: money.call("Sum of the monthly target of goals behind pace"),
                 needs_this_month_cents: cents,
                 on_track_count: { type: :integer },
                 tracked_total: { type: :integer, description: "Goals with a pace to compare against" },
                 reached_count: { type: :integer },
                 behind_count: { type: :integer },
                 no_date_count: { type: :integer },
                 paused_count: { type: :integer },
                 active_total: { type: :integer, description: "Active and paused goals" },
                 saved: money.call("Total held for the goals"),
                 saved_cents: cents,
                 target: money.call("Total of the goals' targets"),
                 target_cents: cents,
                 pending_pledges_count: { type: :integer }
               }
        run_test!
      end

      response "401", "unauthorized" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:"X-Api-Key") { nil }
        run_test!
      end

      response "403", "preview features disabled" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        before { user.update!(preferences: { "preview_features_enabled" => false }) }
        run_test!
      end
    end
  end

  path "/api/v1/goals/{id}" do
    parameter name: :id, in: :path, required: true, schema: { type: :string, format: :uuid }
    let(:id) { goal.id }

    get "Show goal" do
      tags "Goals"
      security [ { apiKeyAuth: [] } ]
      produces "application/json"

      response "200", "goal" do
        schema goal_schema
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end

    patch "Update goal" do
      tags "Goals"
      security [ { apiKeyAuth: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, required: true, schema: goal_input_schema

      response "200", "goal updated" do
        schema goal_schema
        let(:body) { { goal: { name: "Trip to Rome", target_amount: 6000 } } }
        run_test!
      end

      response "422", "validation failed" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:body) { { goal: { account_ids: [ "" ] } } }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:id) { SecureRandom.uuid }
        let(:body) { { goal: { name: "x" } } }
        run_test!
      end
    end

    delete "Delete goal" do
      tags "Goals"
      description "Deletes the goal, its account links and its pledges. Accounts and transactions are untouched."
      security [ { apiKeyAuth: [] } ]
      produces "application/json"

      response "200", "goal deleted" do
        schema "$ref" => "#/components/schemas/DeleteResponse"
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end
  end

  %w[pause resume complete archive unarchive reopen].each do |event|
    path "/api/v1/goals/{id}/#{event}" do
      parameter name: :id, in: :path, required: true, schema: { type: :string, format: :uuid }
      let(:id) { goal.id }

      patch "#{event.capitalize} goal" do
        tags "Goals"
        description "Fires the goal's #{event} transition, as on the web goal page. No body. " \
                    "Returns 422 invalid_transition, with a message to show as-is, when the goal's state does not allow it."
        security [ { apiKeyAuth: [] } ]
        produces "application/json"

        allowed_from = {
          "pause" => nil, "resume" => :pause!, "complete" => nil,
          "archive" => nil, "unarchive" => :archive!, "reopen" => :complete!
        }.fetch(event)
        refused_from = {
          "pause" => :pause!, "resume" => nil, "complete" => :archive!,
          "archive" => :archive!, "unarchive" => nil, "reopen" => nil
        }.fetch(event)

        response "200", "transition applied" do
          schema goal_schema
          before { goal.public_send(allowed_from) if allowed_from }
          run_test!
        end

        response "422", "transition not allowed in the current state" do
          schema "$ref" => "#/components/schemas/ErrorResponse"
          before { goal.public_send(refused_from) if refused_from }
          run_test!
        end

        response "404", "not found" do
          schema "$ref" => "#/components/schemas/ErrorResponse"
          let(:id) { SecureRandom.uuid }
          run_test!
        end
      end
    end
  end

  path "/api/v1/goals/{id}/consume" do
    parameter name: :id, in: :path, required: true, schema: { type: :string, format: :uuid }
    let(:id) { goal.id }

    post "Record a spend against a goal" do
      tags "Goals"
      description "The web's \"I used some of this money\" flow. Adds to consumed_amount and releases the same amount " \
                  "from the account's earmark. Pass either amount (plus account_id when the caller can see more than one " \
                  "linked account) or transaction_id to attribute a detected outflow, whose amount and account are used. " \
                  "Only one-off active goals can be spent from; refusals return 422 consumption_refused with a reason."
      security [ { apiKeyAuth: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[consumption],
        properties: {
          consumption: {
            type: :object,
            properties: {
              amount: { type: :number, description: "In goal currency; ignored when transaction_id is given" },
              account_id: { type: :string, format: :uuid, description: "Linked account the money came out of" },
              transaction_id: { type: :string, format: :uuid, description: "An unattributed outflow on a linked account" }
            }
          }
        }
      }

      response "201", "spend recorded" do
        schema goal_schema
        let(:body) { { consumption: { amount: 200 } } }
        run_test!
      end

      response "422", "spend refused" do
        schema type: :object, required: %w[error message],
               properties: {
                 error: { type: :string, enum: %w[consumption_refused validation_failed] },
                 reason: { type: :string, enum: %w[non_positive maintained exceeds_target account_required account_not_linked
                                                   not_active exceeds_earmark transaction_already_claimed transaction_not_found
                                                   no_linked_account missing_exchange_rate] },
                 message: { type: :string },
                 errors: { type: :array, items: { type: :string } }
               }
        let(:body) { { consumption: { amount: 0 } } }
        run_test!
      end

      response "404", "not found" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:id) { SecureRandom.uuid }
        let(:body) { { consumption: { amount: 200 } } }
        run_test!
      end
    end
  end

  path "/api/v1/goals/{goal_id}/pledges" do
    parameter name: :goal_id, in: :path, required: true, schema: { type: :string, format: :uuid }
    let(:goal_id) { goal.id }

    post "Pledge a contribution to a goal" do
      tags "Goals"
      description "Records that the user just moved money toward the goal. Sync matches the pledge against the incoming transfer (or a manual balance update) and closes it; unmatched pledges expire after 7 days. Returns the pledge and the refreshed goal."
      security [ { apiKeyAuth: [] } ]
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          pledge: {
            type: :object,
            required: %w[amount account_id],
            properties: {
              amount: { type: :number, description: "In goal currency" },
              account_id: { type: :string, format: :uuid, description: "A linked account the caller can access" }
            }
          }
        }
      }

      response "201", "pledge created" do
        schema pledge_response_schema
        let(:body) { { pledge: { amount: 200, account_id: account.id } } }
        run_test!
      end

      response "422", "validation failed" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:body) { { pledge: { amount: 0, account_id: account.id } } }
        run_test!
      end

      response "404", "goal not found" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:goal_id) { SecureRandom.uuid }
        let(:body) { { pledge: { amount: 200, account_id: account.id } } }
        run_test!
      end
    end
  end

  path "/api/v1/goals/{goal_id}/pledges/{id}" do
    parameter name: :goal_id, in: :path, required: true, schema: { type: :string, format: :uuid }
    parameter name: :id, in: :path, required: true, schema: { type: :string, format: :uuid }
    let(:goal_id) { goal.id }
    let(:pledge) { goal.goal_pledges.create!(account: account, amount: 200, currency: "USD") }
    let(:id) { pledge.id }

    delete "Cancel a pledge" do
      tags "Goals"
      description "Cancels an open pledge (it is kept with status cancelled). Returns the pledge and the refreshed goal."
      security [ { apiKeyAuth: [] } ]
      produces "application/json"

      response "200", "pledge cancelled" do
        schema pledge_response_schema
        run_test!
      end

      response "422", "pledge is not open" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        before { pledge.cancel! }
        run_test!
      end

      response "404", "pledge not found" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        let(:id) { SecureRandom.uuid }
        run_test!
      end
    end
  end

  path "/api/v1/goals/{goal_id}/pledges/{id}/renew" do
    parameter name: :goal_id, in: :path, required: true, schema: { type: :string, format: :uuid }
    parameter name: :id, in: :path, required: true, schema: { type: :string, format: :uuid }
    let(:goal_id) { goal.id }
    let(:pledge) { goal.goal_pledges.create!(account: account, amount: 200, currency: "USD") }
    let(:id) { pledge.id }

    patch "Extend a pledge by 7 days" do
      tags "Goals"
      security [ { apiKeyAuth: [] } ]
      produces "application/json"

      response "200", "pledge extended" do
        schema pledge_response_schema
        run_test!
      end

      response "422", "pledge is not open" do
        schema "$ref" => "#/components/schemas/ErrorResponse"
        before { pledge.cancel! }
        run_test!
      end
    end
  end
end
