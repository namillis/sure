# Sets the family's whole rule order from one list of rule ids, top to bottom,
# for clients that show the rules as a flat list. Rule::Layout keeps a group's
# rules as one block, so the list must list them together. A group with no
# rules has no place in the list; it stays right after the item it follows now.
class Rule::FlatReorder
  def initialize(family)
    @family = family
  end

  def reorder!(rule_ids)
    rule_ids = Array(rule_ids).map(&:to_s)

    Rule.transaction do
      Rule.lock_positions!(family)

      rules_by_id = family.rules.index_by(&:id)
      unless rule_ids.size == rules_by_id.size && rule_ids.sort == rules_by_id.keys.sort
        raise ArgumentError, "rule_ids must list every rule of the family exactly once"
      end

      blocks = rule_ids.map { |id| rules_by_id.fetch(id) }
        .chunk_while { |above, below| above.rule_group_id.present? && above.rule_group_id == below.rule_group_id }
        .to_a
      group_ids = blocks.filter_map { |block| block.first.rule_group_id }
      raise ArgumentError, "rules of the same group must be listed together" if group_ids.uniq.size != group_ids.size

      layout = Rule::Layout.new(family)
      layout.reorder!(top_level_keys(blocks, layout.items))
      family.rule_groups.where(id: group_ids).each do |group|
        block = blocks.find { |rules| rules.first.rule_group_id == group.id }
        layout.reorder_group!(group, block.map(&:id))
      end
    end
  end

  private
    attr_reader :family

    def top_level_keys(blocks, current_items)
      keys = blocks.map do |block|
        group_id = block.first.rule_group_id
        group_id ? "group:#{group_id}" : "rule:#{block.first.id}"
      end

      previous_key = nil
      current_items.each do |item|
        keys.insert(previous_key ? keys.index(previous_key) + 1 : 0, item.key) if item.group? && item.rules.empty?
        previous_key = item.key
      end

      keys
    end
end
