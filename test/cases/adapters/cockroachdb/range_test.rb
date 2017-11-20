# frozen_string_literal: true

require "cases/helper"
require "support/connection_helper"

if ActiveRecord::Base.connection.respond_to?(:supports_ranges?) && ActiveRecord::Base.connection.supports_ranges?
  class CockroachdbRange < ActiveRecord::Base
    self.table_name = "postgresql_ranges"
    self.time_zone_aware_types += [:tsrange, :tstzrange]
  end

  class CockroachdbRangeTest < ActiveRecord::CockroachDBTestCase
    self.use_transactional_tests = false
    include ConnectionHelper
    include InTimeZone

    def setup
      @connection = CockroachdbRange.connection
      begin
        @connection.transaction do
          @connection.execute <<_SQL
            CREATE TYPE floatrange AS RANGE (
                subtype = float8,
                subtype_diff = float8mi
            );
_SQL

          @connection.create_table("postgresql_ranges") do |t|
            t.daterange :date_range
            t.numrange :num_range
            t.tsrange :ts_range
            t.tstzrange :tstz_range
            t.int4range :int4_range
            t.int8range :int8_range
          end

          @connection.add_column "postgresql_ranges", "float_range", "floatrange"
        end
        CockroachdbRange.reset_column_information
      rescue ActiveRecord::StatementInvalid
        skip "do not test on PG without range"
      end

      insert_range(id: 101,
                   date_range: "[''2012-01-02'', ''2012-01-04'']",
                   num_range: "[0.1, 0.2]",
                   ts_range: "[''2010-01-01 14:30'', ''2011-01-01 14:30'']",
                   tstz_range: "[''2010-01-01 14:30:00+05'', ''2011-01-01 14:30:00-03'']",
                   int4_range: "[1, 10]",
                   int8_range: "[10, 100]",
                   float_range: "[0.5, 0.7]")

      insert_range(id: 102,
                   date_range: "[''2012-01-02'', ''2012-01-04'')",
                   num_range: "[0.1, 0.2)",
                   ts_range: "[''2010-01-01 14:30'', ''2011-01-01 14:30'')",
                   tstz_range: "[''2010-01-01 14:30:00+05'', ''2011-01-01 14:30:00-03'')",
                   int4_range: "[1, 10)",
                   int8_range: "[10, 100)",
                   float_range: "[0.5, 0.7)")

      insert_range(id: 103,
                   date_range: "[''2012-01-02'',]",
                   num_range: "[0.1,]",
                   ts_range: "[''2010-01-01 14:30'',]",
                   tstz_range: "[''2010-01-01 14:30:00+05'',]",
                   int4_range: "[1,]",
                   int8_range: "[10,]",
                   float_range: "[0.5,]")

      insert_range(id: 104,
                   date_range: "[,]",
                   num_range: "[,]",
                   ts_range: "[,]",
                   tstz_range: "[,]",
                   int4_range: "[,]",
                   int8_range: "[,]",
                   float_range: "[,]")

      insert_range(id: 105,
                   date_range: "[''2012-01-02'', ''2012-01-02'')",
                   num_range: "[0.1, 0.1)",
                   ts_range: "[''2010-01-01 14:30'', ''2010-01-01 14:30'')",
                   tstz_range: "[''2010-01-01 14:30:00+05'', ''2010-01-01 06:30:00-03'')",
                   int4_range: "[1, 1)",
                   int8_range: "[10, 10)",
                   float_range: "[0.5, 0.5)")

      @new_range = CockroachdbRange.new
      @first_range = CockroachdbRange.find(101)
      @second_range = CockroachdbRange.find(102)
      @third_range = CockroachdbRange.find(103)
      @fourth_range = CockroachdbRange.find(104)
      @empty_range = CockroachdbRange.find(105)
    end

    teardown do
      @connection.drop_table "postgresql_ranges", if_exists: true
      @connection.execute "DROP TYPE IF EXISTS floatrange"
      reset_connection
    end

    def test_data_type_of_range_types
      assert_equal :daterange, @first_range.column_for_attribute(:date_range).type
      assert_equal :numrange, @first_range.column_for_attribute(:num_range).type
      assert_equal :tsrange, @first_range.column_for_attribute(:ts_range).type
      assert_equal :tstzrange, @first_range.column_for_attribute(:tstz_range).type
      assert_equal :int4range, @first_range.column_for_attribute(:int4_range).type
      assert_equal :int8range, @first_range.column_for_attribute(:int8_range).type
    end

    def test_int4range_values
      assert_equal 1...11, @first_range.int4_range
      assert_equal 1...10, @second_range.int4_range
      assert_equal 1...Float::INFINITY, @third_range.int4_range
      assert_equal(-Float::INFINITY...Float::INFINITY, @fourth_range.int4_range)
      assert_nil @empty_range.int4_range
    end

    def test_int8range_values
      assert_equal 10...101, @first_range.int8_range
      assert_equal 10...100, @second_range.int8_range
      assert_equal 10...Float::INFINITY, @third_range.int8_range
      assert_equal(-Float::INFINITY...Float::INFINITY, @fourth_range.int8_range)
      assert_nil @empty_range.int8_range
    end

    def test_daterange_values
      assert_equal Date.new(2012, 1, 2)...Date.new(2012, 1, 5), @first_range.date_range
      assert_equal Date.new(2012, 1, 2)...Date.new(2012, 1, 4), @second_range.date_range
      assert_equal Date.new(2012, 1, 2)...Float::INFINITY, @third_range.date_range
      assert_equal(-Float::INFINITY...Float::INFINITY, @fourth_range.date_range)
      assert_nil @empty_range.date_range
    end

    def test_numrange_values
      assert_equal BigDecimal.new("0.1")..BigDecimal.new("0.2"), @first_range.num_range
      assert_equal BigDecimal.new("0.1")...BigDecimal.new("0.2"), @second_range.num_range
      assert_equal BigDecimal.new("0.1")...BigDecimal.new("Infinity"), @third_range.num_range
      assert_equal BigDecimal.new("-Infinity")...BigDecimal.new("Infinity"), @fourth_range.num_range
      assert_nil @empty_range.num_range
    end

    def test_tsrange_values
      tz = ::ActiveRecord::Base.default_timezone
      assert_equal Time.send(tz, 2010, 1, 1, 14, 30, 0)..Time.send(tz, 2011, 1, 1, 14, 30, 0), @first_range.ts_range
      assert_equal Time.send(tz, 2010, 1, 1, 14, 30, 0)...Time.send(tz, 2011, 1, 1, 14, 30, 0), @second_range.ts_range
      assert_equal(-Float::INFINITY...Float::INFINITY, @fourth_range.ts_range)
      assert_nil @empty_range.ts_range
    end

    def test_tstzrange_values
      assert_equal Time.parse("2010-01-01 09:30:00 UTC")..Time.parse("2011-01-01 17:30:00 UTC"), @first_range.tstz_range
      assert_equal Time.parse("2010-01-01 09:30:00 UTC")...Time.parse("2011-01-01 17:30:00 UTC"), @second_range.tstz_range
      assert_equal(-Float::INFINITY...Float::INFINITY, @fourth_range.tstz_range)
      assert_nil @empty_range.tstz_range
    end

    def test_custom_range_values
      assert_equal 0.5..0.7, @first_range.float_range
      assert_equal 0.5...0.7, @second_range.float_range
      assert_equal 0.5...Float::INFINITY, @third_range.float_range
      assert_equal(-Float::INFINITY...Float::INFINITY, @fourth_range.float_range)
      assert_nil @empty_range.float_range
    end

    def test_timezone_awareness_tzrange
      tz = "Pacific Time (US & Canada)"

      in_time_zone tz do
        CockroachdbRange.reset_column_information
        time_string = Time.current.to_s
        time = Time.zone.parse(time_string)

        record = CockroachdbRange.new(tstz_range: time_string..time_string)
        assert_equal time..time, record.tstz_range
        assert_equal ActiveSupport::TimeZone[tz], record.tstz_range.begin.time_zone

        record.save!
        record.reload

        assert_equal time..time, record.tstz_range
        assert_equal ActiveSupport::TimeZone[tz], record.tstz_range.begin.time_zone
      end
    end

    def test_create_tstzrange
      tstzrange = Time.parse("2010-01-01 14:30:00 +0100")...Time.parse("2011-02-02 14:30:00 CDT")
      round_trip(@new_range, :tstz_range, tstzrange)
      assert_equal @new_range.tstz_range, tstzrange
      assert_equal @new_range.tstz_range, Time.parse("2010-01-01 13:30:00 UTC")...Time.parse("2011-02-02 19:30:00 UTC")
    end

    def test_update_tstzrange
      assert_equal_round_trip(@first_range, :tstz_range,
                              Time.parse("2010-01-01 14:30:00 CDT")...Time.parse("2011-02-02 14:30:00 CET"))
      assert_nil_round_trip(@first_range, :tstz_range,
                            Time.parse("2010-01-01 14:30:00 +0100")...Time.parse("2010-01-01 13:30:00 +0000"))
    end

    def test_create_tsrange
      tz = ::ActiveRecord::Base.default_timezone
      assert_equal_round_trip(@new_range, :ts_range,
                              Time.send(tz, 2010, 1, 1, 14, 30, 0)...Time.send(tz, 2011, 2, 2, 14, 30, 0))
    end

    def test_update_tsrange
      tz = ::ActiveRecord::Base.default_timezone
      assert_equal_round_trip(@first_range, :ts_range,
                              Time.send(tz, 2010, 1, 1, 14, 30, 0)...Time.send(tz, 2011, 2, 2, 14, 30, 0))
      assert_nil_round_trip(@first_range, :ts_range,
                            Time.send(tz, 2010, 1, 1, 14, 30, 0)...Time.send(tz, 2010, 1, 1, 14, 30, 0))
    end

    def test_timezone_awareness_tsrange
      tz = "Pacific Time (US & Canada)"

      in_time_zone tz do
        CockroachdbRange.reset_column_information
        time_string = Time.current.to_s
        time = Time.zone.parse(time_string)

        record = CockroachdbRange.new(ts_range: time_string..time_string)
        assert_equal time..time, record.ts_range
        assert_equal ActiveSupport::TimeZone[tz], record.ts_range.begin.time_zone

        record.save!
        record.reload

        assert_equal time..time, record.ts_range
        assert_equal ActiveSupport::TimeZone[tz], record.ts_range.begin.time_zone
      end
    end

    def test_create_tstzrange_preserve_usec
      tstzrange = Time.parse("2010-01-01 14:30:00.670277 +0100")...Time.parse("2011-02-02 14:30:00.745125 CDT")
      round_trip(@new_range, :tstz_range, tstzrange)
      assert_equal @new_range.tstz_range, tstzrange
      assert_equal @new_range.tstz_range, Time.parse("2010-01-01 13:30:00.670277 UTC")...Time.parse("2011-02-02 19:30:00.745125 UTC")
    end

    def test_update_tstzrange_preserve_usec
      assert_equal_round_trip(@first_range, :tstz_range,
                              Time.parse("2010-01-01 14:30:00.245124 CDT")...Time.parse("2011-02-02 14:30:00.451274 CET"))
      assert_nil_round_trip(@first_range, :tstz_range,
                            Time.parse("2010-01-01 14:30:00.245124 +0100")...Time.parse("2010-01-01 13:30:00.245124 +0000"))
    end

    def test_create_tsrange_preseve_usec
      tz = ::ActiveRecord::Base.default_timezone
      assert_equal_round_trip(@new_range, :ts_range,
                              Time.send(tz, 2010, 1, 1, 14, 30, 0, 125435)...Time.send(tz, 2011, 2, 2, 14, 30, 0, 225435))
    end

    def test_update_tsrange_preserve_usec
      tz = ::ActiveRecord::Base.default_timezone
      assert_equal_round_trip(@first_range, :ts_range,
                              Time.send(tz, 2010, 1, 1, 14, 30, 0, 142432)...Time.send(tz, 2011, 2, 2, 14, 30, 0, 224242))
      assert_nil_round_trip(@first_range, :ts_range,
                            Time.send(tz, 2010, 1, 1, 14, 30, 0, 142432)...Time.send(tz, 2010, 1, 1, 14, 30, 0, 142432))
    end

    def test_timezone_awareness_tsrange_preserve_usec
      tz = "Pacific Time (US & Canada)"

      in_time_zone tz do
        CockroachdbRange.reset_column_information
        time_string = "2017-09-26 07:30:59.132451 -0700"
        time = Time.zone.parse(time_string)
        assert time.usec > 0

        record = CockroachdbRange.new(ts_range: time_string..time_string)
        assert_equal time..time, record.ts_range
        assert_equal ActiveSupport::TimeZone[tz], record.ts_range.begin.time_zone
        assert_equal time.usec, record.ts_range.begin.usec

        record.save!
        record.reload

        assert_equal time..time, record.ts_range
        assert_equal ActiveSupport::TimeZone[tz], record.ts_range.begin.time_zone
        assert_equal time.usec, record.ts_range.begin.usec
      end
    end

    def test_create_numrange
      assert_equal_round_trip(@new_range, :num_range,
                              BigDecimal.new("0.5")...BigDecimal.new("1"))
    end

    def test_update_numrange
      assert_equal_round_trip(@first_range, :num_range,
                              BigDecimal.new("0.5")...BigDecimal.new("1"))
      assert_nil_round_trip(@first_range, :num_range,
                            BigDecimal.new("0.5")...BigDecimal.new("0.5"))
    end

    def test_create_daterange
      assert_equal_round_trip(@new_range, :date_range,
                              Range.new(Date.new(2012, 1, 1), Date.new(2013, 1, 1), true))
    end

    def test_update_daterange
      assert_equal_round_trip(@first_range, :date_range,
                              Date.new(2012, 2, 3)...Date.new(2012, 2, 10))
      assert_nil_round_trip(@first_range, :date_range,
                            Date.new(2012, 2, 3)...Date.new(2012, 2, 3))
    end

    def test_create_int4range
      assert_equal_round_trip(@new_range, :int4_range, Range.new(3, 50, true))
    end

    def test_update_int4range
      assert_equal_round_trip(@first_range, :int4_range, 6...10)
      assert_nil_round_trip(@first_range, :int4_range, 3...3)
    end

    def test_create_int8range
      assert_equal_round_trip(@new_range, :int8_range, Range.new(30, 50, true))
    end

    def test_update_int8range
      assert_equal_round_trip(@first_range, :int8_range, 60000...10000000)
      assert_nil_round_trip(@first_range, :int8_range, 39999...39999)
    end

    def test_exclude_beginning_for_subtypes_without_succ_method_is_not_supported
      assert_raises(ArgumentError) { CockroachdbRange.create!(num_range: "(0.1, 0.2]") }
      assert_raises(ArgumentError) { CockroachdbRange.create!(float_range: "(0.5, 0.7]") }
      assert_raises(ArgumentError) { CockroachdbRange.create!(int4_range: "(1, 10]") }
      assert_raises(ArgumentError) { CockroachdbRange.create!(int8_range: "(10, 100]") }
      assert_raises(ArgumentError) { CockroachdbRange.create!(date_range: "(''2012-01-02'', ''2012-01-04'']") }
      assert_raises(ArgumentError) { CockroachdbRange.create!(ts_range: "(''2010-01-01 14:30'', ''2011-01-01 14:30'']") }
      assert_raises(ArgumentError) { CockroachdbRange.create!(tstz_range: "(''2010-01-01 14:30:00+05'', ''2011-01-01 14:30:00-03'']") }
    end

    def test_where_by_attribute_with_range
      range = 1..100
      record = CockroachdbRange.create!(int4_range: range)
      assert_equal record, CockroachdbRange.where(int4_range: range).take
    end

    def test_update_all_with_ranges
      CockroachdbRange.create!

      CockroachdbRange.update_all(int8_range: 1..100)

      assert_equal 1...101, CockroachdbRange.first.int8_range
    end

    def test_ranges_correctly_escape_input
      range = "-1,2]'; DROP TABLE postgresql_ranges; --".."a"
      CockroachdbRange.update_all(int8_range: range)

      assert_nothing_raised do
        CockroachdbRange.first
      end
    end

    private
      def assert_equal_round_trip(range, attribute, value)
        round_trip(range, attribute, value)
        assert_equal value, range.public_send(attribute)
      end

      def assert_nil_round_trip(range, attribute, value)
        round_trip(range, attribute, value)
        assert_nil range.public_send(attribute)
      end

      def round_trip(range, attribute, value)
        range.public_send "#{attribute}=", value
        assert range.save
        assert range.reload
      end

      def insert_range(values)
        @connection.execute <<-SQL
          INSERT INTO postgresql_ranges (
            id,
            date_range,
            num_range,
            ts_range,
            tstz_range,
            int4_range,
            int8_range,
            float_range
          ) VALUES (
            #{values[:id]},
            '#{values[:date_range]}',
            '#{values[:num_range]}',
            '#{values[:ts_range]}',
            '#{values[:tstz_range]}',
            '#{values[:int4_range]}',
            '#{values[:int8_range]}',
            '#{values[:float_range]}'
          )
        SQL
      end
  end
end
