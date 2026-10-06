module ActiveModel
  module Validations
    class TransitionValidator < ActiveModel::Validator
      def initialize(options)
        super
        @column              = options[:column].to_s
        valid_transitions    = options[:valid_transitions]
        @when_validations    = options[:when_validations]&.to_h { |attribute, values| [attribute, [values].flatten] }
        @inclusive           = options[:inclusive]
        @allowed_transitions = {}

        build_valid_transition_lookup(valid_transitions)
      end

      def build_valid_transition_lookup(valid_transitions)
        valid_transitions.each do |transition|
          requires = transition[:requires].present? &&
                     transition[:requires].to_h { |key, value| [key, [value].flatten] }

          [transition[:from]].flatten.each do |from|
            to_lookup = (@allowed_transitions[from] ||= {})
            [transition[:to]].flatten.each do |to|
              # First matching definition wins, preserving the previous ordered-lookup behavior
              to_lookup[to] ||= { requires_validation: !!requires, requires: requires }
            end
          end
        end
      end

      def validate(record)
        return true if @when_validations && when_condition_unmet?(record)
        return true unless record.persisted?

        changes = record.changes
        return true unless changes.has_key?(@column)

        column_change     = changes[@column]
        original_value    = column_change[0]
        new_value         = column_change[1]
        valid_transitions = @allowed_transitions[original_value]

        if valid_transitions.nil?
          add_inclusion_errors(record, original_value, new_value) if @inclusive
          return true
        end

        transition = valid_transitions[new_value]
        return invalid_transition_error(record, original_value, new_value) unless transition
        return true unless transition[:requires_validation]

        validate_requires_field(transition[:requires], original_value, new_value, record)
      end

      private

      def add_inclusion_errors(record, original_value, new_value)
        record.errors.add(
          @column.to_sym,
          "#{@column} cannot transition from #{original_value} to #{new_value}."
        )
      end

      def when_condition_unmet?(record)
        !@when_validations.all? do |attribute, when_values|
          when_values.include?(record.read_attribute(attribute))
        end
      end

      def validate_requires_field(all_requires, original_value, new_value, record)
        all_requires.each do |attribute, allowed_values|
          current_value = record.read_attribute(attribute)
          next if allowed_values.include?(current_value)

          add_requires_error(record, original_value, new_value, attribute, current_value)
        end
      end

      def invalid_transition_error(record, original_value, new_value)
        record.errors.add(
          @column.to_sym,
          "#{@column} cannot transition from #{original_value} to #{new_value}"
        )
      end

      def add_requires_error(record, original_value, new_value, required_column_name, current_required_value)
        record.errors.add(
          @column.to_sym,
          "#{@column} cannot transition from #{original_value} to #{new_value} while #{required_column_name} is #{current_required_value}"
        )
      end

    end
  end
end
