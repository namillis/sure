# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'API V1 AI Settings', type: :request do
  let(:family) do
    Family.create!(
      name: 'API Family',
      currency: 'USD',
      locale: 'en',
      date_format: '%m-%d-%Y'
    )
  end

  let(:user) do
    family.users.create!(
      email: 'api-user@example.com',
      password: 'password123',
      password_confirmation: 'password123',
      role: 'admin'
    )
  end

  let(:api_key) do
    key = ApiKey.generate_secure_key
    ApiKey.create!(
      user: user,
      name: 'API Docs Key',
      key: key,
      scopes: %w[read_write],
      source: 'web'
    )
  end

  let(:'X-Api-Key') { api_key.plain_key }

  admin_only = 'Family admins only, as the web page is; members and guests get 403 `forbidden`.'

  cost_properties = lambda do |name, description|
    {
      name => { type: :string, description: "#{description}, formatted in USD as the web page shows it" },
      "#{name}_cents" => { type: :integer, description: 'Rounded to whole cents' },
      "#{name}_amount" => { type: :string, description: 'Unrounded decimal USD; most single requests cost under a cent' }
    }
  end

  count_properties = {
    total_requests: { type: :integer },
    requests_with_cost: { type: :integer, description: 'Requests with a known price; costs only count these' },
    total_prompt_tokens: { type: :integer },
    total_completion_tokens: { type: :integer },
    total_tokens: { type: :integer }
  }

  ai_settings_schema = {
    type: :object,
    required: %w[ai_settings],
    properties: {
      ai_settings: {
        type: :object,
        required: %w[ai_available ai_enabled prompt_max_length prompts classifier],
        properties: {
          ai_available: { type: :boolean, description: 'Whether this server has an AI provider for the user (User#ai_available?)' },
          ai_enabled: { type: :boolean, description: 'Whether the user has AI turned on and it is available' },
          prompt_max_length: { type: :integer },
          prompts: {
            type: :array,
            items: {
              type: :object,
              required: %w[key value default custom format_risk format_risk_key],
              properties: {
                key: { type: :string, enum: Family::AiPromptable::KEYS.map(&:to_s) },
                value: { type: :string, nullable: true, description: "The family's override, or null when it runs the default" },
                default: { type: :string, description: 'The built-in prompt this server sends without an override' },
                custom: { type: :boolean },
                format_risk: { type: :boolean, description: 'The override dropped the JSON key the custom-endpoint prompt asks for (advisory)' },
                format_risk_key: { type: :string, nullable: true }
              }
            }
          },
          classifier: {
            type: :object,
            required: %w[settings defaults default ranges choices rules evaluation],
            properties: {
              settings: { type: :object, additionalProperties: true, description: 'Every Family::BayesSettings value' },
              defaults: { type: :object, additionalProperties: true },
              default: { type: :boolean, description: 'All settings are at their defaults' },
              ranges: { type: :object, additionalProperties: { type: :object, properties: { min: { type: :number }, max: { type: :number } } } },
              choices: { type: :object, additionalProperties: { type: :array, items: { type: :string } } },
              rules: {
                type: :array,
                items: {
                  type: :object,
                  required: %w[action_type name exists active],
                  properties: {
                    action_type: { type: :string, enum: Family::CLASSIFIER_ACTION_TYPES },
                    name: { type: :string },
                    exists: { type: :boolean, description: 'False once the rule was deleted on the Rules page' },
                    active: { type: :boolean }
                  }
                }
              },
              evaluation: {
                type: :object,
                properties: {
                  running: { type: :boolean },
                  ran_at: { type: :string, format: 'date-time', nullable: true },
                  action: { type: :string, nullable: true },
                  settings_changed_since: { type: :boolean, nullable: true }
                }
              }
            }
          }
        }
      }
    }
  }

  queued_schema = {
    type: :object,
    required: %w[data],
    properties: {
      data: {
        type: :object,
        required: %w[status job],
        properties: { status: { type: :string, enum: %w[queued] }, job: { type: :string } }
      }
    }
  }

  path '/api/v1/settings/ai' do
    get 'Show the AI prompts and classifier settings' do
      tags 'Settings'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      description "Settings → AI prompts and Settings → Classifier. #{admin_only} Never includes provider keys."

      response '200', 'AI settings' do
        schema ai_settings_schema
        run_test!
      end

      response '401', 'unauthorized' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        let(:'X-Api-Key') { nil }
        run_test!
      end
    end

    patch 'Update the AI prompts and classifier settings' do
      tags 'Settings'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      description <<~DESC
        #{admin_only} Needs `read_write`. Send any of the three parts; the rest stay as they are.
        A blank or null prompt resets it to the default. Classifier numbers are clamped to `ranges`, as on the web.
        Turning on a classifier rule that was deleted returns 422 `classifier_rule_missing`; add it with
        `POST /api/v1/settings/ai/classifier/rules`. All changes save together or not at all.
      DESC
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[ai_settings],
        properties: {
          ai_settings: {
            type: :object,
            properties: {
              prompts: { type: :object, additionalProperties: { type: :string, nullable: true }, description: 'Prompt key => text' },
              classifier: {
                type: :object,
                properties: {
                  settings: { type: :object, additionalProperties: true, description: 'Any classifier setting keys, e.g. threshold, excluded_category_ids' },
                  rules_active: { type: :object, additionalProperties: { type: :boolean }, description: 'action_type => on/off' }
                }
              }
            }
          }
        }
      }

      let(:body) { { ai_settings: { prompts: { chat_system: 'Be brief.' }, classifier: { settings: { threshold: 0.6 } } } } }

      response '200', 'AI settings updated' do
        schema ai_settings_schema
        run_test!
      end

      response '422', 'invalid settings' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        let(:body) { { ai_settings: { prompts: { unknown_prompt: 'x' } } } }
        run_test!
      end
    end
  end

  path '/api/v1/settings/ai/classifier/run' do
    post 'Run the classifier over uncategorized transactions' do
      tags 'Settings'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      description "Settings → Classifier → Run: queues the matcher (when its rule is on) and Bayes. #{admin_only} Needs `read_write`."

      response '202', 'classifier queued' do
        schema queued_schema
        run_test!
      end
    end
  end

  path '/api/v1/settings/ai/classifier/clear_locks' do
    post 'Unlock what the classifier locked' do
      tags 'Settings'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      description "Settings → Classifier → Clear locks: queues unlocking the categories and merchants Bayes and the matcher locked. #{admin_only} Needs `read_write`."

      response '202', 'unlock queued' do
        schema queued_schema
        run_test!
      end
    end
  end

  path '/api/v1/settings/ai/classifier/rules' do
    post 'Add a deleted classifier rule again' do
      tags 'Settings'
      security [ { apiKeyAuth: [] } ]
      consumes 'application/json'
      produces 'application/json'
      description "Adds the rule at the top of the rule order, active, as the web's \"add it again?\" dialog does. 409 if it exists. #{admin_only}"
      parameter name: :body, in: :body, schema: {
        type: :object,
        required: %w[action_type],
        properties: { action_type: { type: :string, enum: Family::CLASSIFIER_ACTION_TYPES } }
      }

      let(:body) { { action_type: 'bayes_categorize' } }

      before { family.classifier_rules('bayes_categorize').destroy_all }

      response '201', 'rule added' do
        schema ai_settings_schema
        run_test!
      end

      response '409', 'rule already exists' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        before { family.add_classifier_rule!('bayes_categorize') }
        run_test!
      end
    end
  end

  path '/api/v1/settings/ai/usage' do
    get 'Show LLM usage and estimated cost' do
      tags 'Settings'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      description <<~DESC
        Settings → LLM usage's totals for the range, plus per model and per day (the family's time zone).
        Defaults to the 30 days before `end_date`, which defaults to today. #{admin_only}
      DESC
      parameter name: :start_date, in: :query, required: false, schema: { type: :string, format: :date }
      parameter name: :end_date, in: :query, required: false, schema: { type: :string, format: :date }

      before do
        LlmUsage.create!(family: family, provider: 'openai', model: 'gpt-4.1', operation: 'chat',
          prompt_tokens: 100, completion_tokens: 50, total_tokens: 150, estimated_cost: 0.0123)
      end

      response '200', 'usage' do
        schema type: :object,
               required: %w[llm_usage],
               properties: {
                 llm_usage: {
                   type: :object,
                   properties: {
                     start_date: { type: :string, format: :date },
                     end_date: { type: :string, format: :date },
                     currency: { type: :string, enum: %w[USD] },
                     **count_properties,
                     **cost_properties.call(:total_cost, 'Total'),
                     **cost_properties.call(:avg_cost, 'Average per priced request'),
                     by_operation: {
                       type: :array,
                       items: { type: :object, properties: { operation: { type: :string }, label: { type: :string }, **cost_properties.call(:cost, 'Cost') } }
                     },
                     by_model: {
                       type: :array,
                       items: { type: :object, properties: { model: { type: :string }, **count_properties, **cost_properties.call(:cost, 'Cost') } }
                     },
                     by_day: {
                       type: :array,
                       items: { type: :object, properties: { date: { type: :string, format: :date }, **count_properties, **cost_properties.call(:cost, 'Cost') } }
                     }
                   }
                 }
               }
        run_test!
      end

      response '422', 'invalid date range' do
        schema '$ref' => '#/components/schemas/ErrorResponse'
        let(:start_date) { '2026-02-01' }
        let(:end_date) { '2026-01-01' }
        run_test!
      end
    end
  end
end
