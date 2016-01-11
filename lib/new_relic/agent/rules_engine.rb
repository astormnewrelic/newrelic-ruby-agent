# encoding: utf-8
# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/rpm/blob/master/LICENSE for complete details.

require 'new_relic/agent/rules_engine/replacement_rule'
require 'new_relic/agent/rules_engine/segment_terms_rule'

module NewRelic
  module Agent
    class RulesEngine
      SEGMENT_SEPARATOR = '/'.freeze
      LEADING_SLASH_REGEX = %r{^/}.freeze

      include Enumerable
      extend Forwardable

      def_delegators :@rules, :size, :inspect, :each, :clear

      def self.create_metric_rules(connect_response)
        specs = connect_response['metric_name_rules'] || []
        rules = specs.map { |spec| ReplacementRule.new(spec) }
        self.new(rules)
      end

      def self.create_transaction_rules(connect_response)
        txn_name_specs     = connect_response['transaction_name_rules']    || []
        segment_rule_specs = connect_response['transaction_segment_terms'] || []

        txn_name_rules = txn_name_specs.map { |s| ReplacementRule.new(s) }

        segment_rules = segment_rule_specs.map do |spec|
          if spec[SegmentTermsRule::PREFIX_KEY] && SegmentTermsRule.valid?(spec)
            SegmentTermsRule.new(spec)
          end
        end

        reject_rules_with_duplicate_prefixes!(segment_rules)

        self.new(txn_name_rules, segment_rules)
      end

      # When multiple rules share the same prefix,
      # only apply the rule with the last instance of the prefix.
      def self.reject_rules_with_duplicate_prefixes!(rules)
        rules.compact!
        rules.reverse!
        rules.uniq! { |rule| rule.prefix }
        rules.reverse!
      end

      def initialize(rules=[], segment_term_rules=[])
        @rules = rules.sort
        @segment_term_rules = segment_term_rules
      end

      def apply_rules(rules, string)
        rules.each do |rule|
          if rule.matches?(string)
            string = rule.apply(string)
            break if rule.terminal?
          end
        end
        string
      end

      def rename(original_string)
        renamed = apply_rules(@rules, original_string)
        return nil unless renamed
        renamed = apply_rules(@segment_term_rules, renamed)
        renamed
      end
    end
  end
end
