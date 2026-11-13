require "test_helper"

class Rule::FlatReorderTest < ActiveSupport::TestCase
  setup do
    @family = families(:empty)
  end

  test "sets the order of loose rules" do
    first = create_rule("First")
    second = create_rule("Second")
    third = create_rule("Third")

    reorder!([ third, first, second ])

    assert_equal [ third, first, second ], @family.rules.ordered.to_a
  end

  test "moves a group as one block and orders the rules inside it" do
    loose = create_rule("Loose")
    group = @family.rule_groups.create!(name: "Food")
    grouped_first = create_rule("Grouped first", group: group)
    grouped_second = create_rule("Grouped second", group: group)

    reorder!([ grouped_second, grouped_first, loose ])

    assert_equal [ grouped_second, grouped_first, loose ], @family.rules.ordered.to_a
    assert_equal [ "group:#{group.id}", "rule:#{loose.id}" ], Rule::Layout.new(@family).items.map(&:key)
  end

  test "keeps an empty group after the item it followed" do
    first = create_rule("First")
    empty_group = @family.rule_groups.create!(name: "Empty")
    second = create_rule("Second")

    reorder!([ second, first ])

    assert_equal [ "rule:#{second.id}", "rule:#{first.id}", "group:#{empty_group.id}" ],
      Rule::Layout.new(@family).items.map(&:key)
  end

  test "keeps an empty group at the top when it is first" do
    empty_group = @family.rule_groups.create!(name: "Empty")
    first = create_rule("First")
    second = create_rule("Second")

    reorder!([ second, first ])

    assert_equal [ "group:#{empty_group.id}", "rule:#{second.id}", "rule:#{first.id}" ],
      Rule::Layout.new(@family).items.map(&:key)
  end

  test "rejects a list that splits a group" do
    group = @family.rule_groups.create!(name: "Food")
    grouped_first = create_rule("Grouped first", group: group)
    loose = create_rule("Loose")
    grouped_second = create_rule("Grouped second", group: group)

    assert_no_changes -> { @family.rules.ordered.pluck(:id) } do
      assert_raises(ArgumentError) { reorder!([ grouped_first, loose, grouped_second ]) }
    end
  end

  test "rejects a list missing, repeating or adding a rule" do
    first = create_rule("First")
    second = create_rule("Second")

    assert_raises(ArgumentError) { reorder!([ first ]) }
    assert_raises(ArgumentError) { reorder!([ first, first ]) }
    assert_raises(ArgumentError) { Rule::FlatReorder.new(@family).reorder!([ first.id, second.id, SecureRandom.uuid ]) }
  end

  private
    def reorder!(rules)
      Rule::FlatReorder.new(@family).reorder!(rules.map(&:id))
    end

    def create_rule(name, group: nil)
      @family.rules.create!(name: name, resource_type: "transaction", rule_group: group,
        actions: [ Rule::Action.new(action_type: "exclude_transaction") ])
    end
end
