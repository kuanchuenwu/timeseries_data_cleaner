function [  ...
            fh, ...
            out_table_raw, ...
            missing_filled_table, ...
            missing_filled_bool_array, ...
            out_table_refined, ...
            max_time ...
            ] = ImportTimeSeriesData( varargin )
    try 
        global FH;
        global DYNAMIC_GROWTH_FACTOR;
        global EXPERIMENTS;
        
        aggregation_methods = { 'median', 'mean', 'max', 'min', 'meanabsval', 'maxabsval', 'minabsval', 'rms' };
        sort_orders = { 'ascend', 'descend' };
        missing_placements = { 'last', 'first', 'auto' };
        
        narginchk( 1, 8 );
        Defaults = { '', {}, true, '', '', 'mean', 'ascend', 'last' };
        nonempty_idx = ~cellfun( 'isempty', varargin );
        Defaults(nonempty_idx) = varargin(nonempty_idx);
        [ input_filename, nonstandard_missing_indicators, standard_input_format_flag, experiment, output_filename, aggregation_method, sort_order, missing_placement ] = Defaults{:};

        assert( FH.WRAPPER.CheckFile( input_filename ) );
        assert( iscell( nonstandard_missing_indicators ) );
        assert( ~isempty( standard_input_format_flag ) && isscalar( standard_input_format_flag ) && islogical( standard_input_format_flag ) );
        assert( isempty( experiment ) || ( isvector( experiment ) && ischar( experiment ) && ismember( lower( experiment ), lower( fieldnames( EXPERIMENTS ) ) ) ) );
        assert( standard_input_format_flag || ~isempty( experiment ) );
        assert( isempty( output_filename ) || ( ~strcmpi( input_filename, output_filename ) && FH.WRAPPER.CheckFile( output_filename, 'w' ) ) );
        assert( ~isempty( aggregation_method ) && isvector( aggregation_method ) && ischar( aggregation_method ) ...
                && ismember( lower( aggregation_method ), lower( aggregation_methods ) ) );
        assert( ~isempty( sort_order ) && isvector( sort_order ) && ischar( sort_order ) && ismember( lower( sort_order ), lower( sort_orders ) ) );
        assert( ~isempty( missing_placement ) && isvector( missing_placement ) && ischar( missing_placement ) && ismember( lower( missing_placement ), ...
                lower( missing_placements ) ) );

        if ( ~standard_input_format_flag )
            [   in_filename, ...
                out_filename ...
                ] = FH.WRAPPER.([ 'CustomInputFileFormat_', experiment ])( input_filename, output_filename );
        else
            in_filename = input_filename;
            out_filename = output_filename;
        end
        
        % %%%%%%%%%%%%%%%%%
        % READ FILE
        % %%%%%%%%%%%%%%%%%

        opts = detectImportOptions( in_filename, 'FileType', 'spreadsheet', 'Sheet', 1, 'TextType', 'char', 'DatetimeType', 'datetime', ...
                                    'ReadVariableNames', true, 'ReadRowNames', false, 'VariableDescriptionsRange', '', 'VariableUnitsRange', '' );
        T_raw = readtable( in_filename, opts, 'UseExcel', false );
        out_table_raw = T_raw;
        
        % %%%%%%%%%%%%%%%%%
        % PROCESS FILE
        % %%%%%%%%%%%%%%%%%

        T_raw_standardized_missing = standardizeMissing( T_raw, nonstandard_missing_indicators );
        [ missing_filled_table, missing_filled_bool_array ] = fillmissing( T_raw_standardized_missing, 'previous', 'EndValues', 'none' );
        T_raw = missing_filled_table;

        bound_cols = struct( 'date_col_idx', [], 'bound_col_idx', [] );
        variable_types = varfun( @class, T_raw, 'OutputFormat', 'cell' );
        for k = 1 : 1 : length( variable_types )
            if ( strcmpi( variable_types{k}, 'datetime' ) ...
                    || any( contains( T_raw.Properties.VariableNames{k}, 'time', 'IgnoreCase', true ) ) ...
                    || any( contains( T_raw.Properties.VariableNames{k}, 'date', 'IgnoreCase', true ) ) ...
                    )
                bound_cols.date_col_idx(end + 1) = k;
                bound_cols.bound_col_idx{end + 1} = [];
            else
                assert( k > 1 );
                bound_cols.bound_col_idx{end}(end + 1) = k;
            end
        end

        T_raw_sorted = T_raw;
        for a = 1 : 1 : length( bound_cols.date_col_idx )
            bundled_cols = [ bound_cols.date_col_idx(a), bound_cols.bound_col_idx{a} ];
            [ uniq_dates, idx_map_orig_to_uniq, idx_map_uniq_to_orig ] = unique( T_raw_sorted.(bundled_cols(1)), 'stable' );
            uniq_dates = rmmissing( uniq_dates );
            for b = 1 : 1 : length( uniq_dates )
                [ found_idx ] = find( T_raw_sorted.(bundled_cols(1)) == uniq_dates(b) );
                found_row_ca = cell( [ 1, length( bundled_cols ) ] );
                found_row_ca{1} = uniq_dates(b);
                for c = 2 : 1 : length( bundled_cols )
                    orig_vals = T_raw_sorted{found_idx, bundled_cols(c)};
                    
                    switch ( lower( aggregation_method ) )
                        case ( lower( 'median' ) )
                            agg_val = median( orig_vals, 'all', 'omitnan' );
                        case ( lower( 'mean' ) )
                            agg_val = mean( orig_vals, 'all', 'omitnan' );
                        case ( lower( 'max' ) )
                            agg_val = max( orig_vals, [], 'all', 'omitnan' );
                        case ( lower( 'min' ) )
                            agg_val = min( orig_vals, [], 'all', 'omitnan' );
                        case ( lower( 'meanabsval' ) )
                            agg_val = mean( abs( orig_vals ), 'all', 'omitnan' );
                        case ( lower( 'maxabsval' ) )
                            agg_val = max( abs( orig_vals ), [], 'all', 'omitnan' );
                        case ( lower( 'minabsval' ) )
                            agg_val = min( abs( orig_vals ), [], 'all', 'omitnan' );
                        case ( lower( 'rms' ) )
                            agg_val = rms( orig_vals );
                        otherwise
                            error( 'ImportTimeSeriesData: Invalid Aggregration Method' );
                    end
                    
                    found_row_ca{c} = agg_val;
                end
                found_row_table = cell2table( found_row_ca );
                T_raw_sorted(found_idx(1), bundled_cols) = found_row_table;
                T_raw_sorted(found_idx(2 : end), bundled_cols) = array2table( repmat( missing, size( T_raw_sorted(found_idx(2 : end), bundled_cols) ) ) );
            end
            
            [ T_raw_sorted(:, T_raw_sorted.Properties.VariableNames(bundled_cols)), T_raw_sort_idx ] = sortrows( T_raw_sorted(:, T_raw_sorted.Properties.VariableNames(bundled_cols)), ...
                T_raw_sorted.Properties.VariableNames(bundled_cols), sort_order, 'MissingPlacement', missing_placement );
        end

        start_dates = cell( length( bound_cols.date_col_idx ), 1 );
        for k = 1 : 1 : length( bound_cols.date_col_idx )
            start_dates{k} = min( T_raw_sorted.(bound_cols.date_col_idx(k)) );
        end
        start_date = max( [ start_dates{:} ] );

        end_dates = cell( length( bound_cols.date_col_idx ), 1 );
        for k = 1 : 1 : length( bound_cols.date_col_idx )
            end_dates{k} = max( T_raw_sorted.(bound_cols.date_col_idx(k)) );
        end
        end_date = min( [ end_dates{:} ] );

        assert( start_date <= end_date );

        T_refined = T_raw_sorted;
            T_refined_counter = 0;
            T_refined_next_power = 1;
        T_refined(:, :) = [];
        T_refined = movevars( T_refined, bound_cols.date_col_idx(1), 'Before', 1 );
        if ( length( bound_cols.date_col_idx ) > 1 )
            T_refined = removevars( T_refined, bound_cols.date_col_idx(2 : end) );
        end
        T_refined.Properties.VariableNames{1} = 'Time';
        curr_date = start_date;
        while ( curr_date <= end_date )
            T_refined_rows = table( curr_date );
            for k = 1 : 1 : length( bound_cols.date_col_idx )
                bundled_cols = [ bound_cols.date_col_idx(k), bound_cols.bound_col_idx{k} ];
                non_date_rows_table = FH.WRAPPER.FindCurrData( curr_date, T_raw_sorted(:, T_raw_sorted.Properties.VariableNames(bundled_cols)) );
                assert( height( non_date_rows_table ) == 1 );
                T_refined_rows(end, (end + 1 ) : (end + width( non_date_rows_table ))) = non_date_rows_table;
            end
            T_refined_rows_copy = T_refined_rows;
            T_refined_counter_old = T_refined_counter;
            T_refined_counter = T_refined_counter + height( T_refined_rows_copy );
            while ( true )
                if ( T_refined_counter >= T_refined_next_power )
                    T_refined((T_refined_counter_old + 1) : T_refined_next_power, :) = ...
                        T_refined_rows_copy(1 : (T_refined_next_power - T_refined_counter_old), :);
                    T_refined_rows_copy(1 : (T_refined_next_power - T_refined_counter_old), :) = [];
                    T_refined_counter_old = T_refined_next_power;
                    T_refined_next_power = T_refined_next_power * DYNAMIC_GROWTH_FACTOR;
                else
                    T_refined((T_refined_counter_old + 1) : T_refined_counter, :) = ...
                        T_refined_rows_copy(1 : (T_refined_counter - T_refined_counter_old), :);
                    T_refined_rows_copy(1 : (T_refined_counter - T_refined_counter_old), :) = [];
                    assert( isempty( T_refined_rows_copy ) );
                    break;
                end
            end
            if ( curr_date < end_date )
                curr_date = FH.WRAPPER.FindNextDate( curr_date, T_raw_sorted(:, T_raw_sorted.Properties.VariableNames(bound_cols.date_col_idx)) );
            else
                break;
            end
        end

        % %%%%%%%%%%%%%%%%%
        % WRITE FILE
        % %%%%%%%%%%%%%%%%%

        if ( ~isempty( out_filename ) )
            writetable( T_refined, out_filename, 'FileType', 'spreadsheet', 'Sheet', 'RefinedInputData', 'Range', 'A1', 'UseExcel', false, 'WriteVariableNames', true );
        end

        % %%%%%%%%%%%%%%%%%
        % CONCLUDE
        % %%%%%%%%%%%%%%%%%

        out_table_refined = T_refined;
        
        max_time = max( out_table_refined.Time );
        
    catch ME 
        rethrow( ME );
    end
end
