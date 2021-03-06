%% Copyright 2019, Travelping GmbH <info@travelping.com>

%% This program is free software; you can redistribute it and/or
%% modify it under the terms of the GNU General Public License
%% as published by the Free Software Foundation; either version
%% 2 of the License, or (at your option) any later version.

-module(gsn_SUITE).

%% Common Test callbacks
-compile([export_all, nowarn_export_all]).

-include_lib("common_test/include/ct.hrl").

-include("ergw_test_lib.hrl").

%%%===================================================================
%%% Common Test callbacks
%%%===================================================================

all() ->
    [gx_pcc_rules].

suite() ->
    [{timetrap, {seconds, 30}}].

groups() ->
    [].

init_per_suite(Config) ->
    %%ok = meck:new(ergw_gsn_lib, [passthrough, no_link]),
    Config.

end_per_suite(_Config) ->
    %%ok = meck:unload(ergw_gsn_lib),
    ok.

%%%===================================================================
%%% Helper
%%%===================================================================

maps_merge(ListOfMaps) ->
    lists:foldl(fun(X,M) -> maps:merge(M,X) end, #{}, ListOfMaps).

%%%===================================================================
%%% Test cases
%%%===================================================================
bin_fmt(Format, Data) ->
    erlang:iolist_to_binary(io_lib:format(Format, Data)).

group(Id) ->
    bin_fmt("r-~4.10.0B", [Id]).

rule_base(Id) ->
    bin_fmt("rb-~4.10.0B", [Id]).

gx_pcc_rules() ->
    [{doc, "Convert Gx DIAMETER Instal/Remove Avps into rules database"}].
gx_pcc_rules(_Config) ->
    RIds = lists:seq(3001, 3004),
    [RG3001, _RG3002, RG3003, _RG3004 ] = RGs =
	[#{'Rating-Group' => [RG],
	   'Flow-Information' =>
	       [#{'Flow-Description' => [<<"permit out ip from any to assigned">>],
		  'Flow-Direction'   => [1]    %% DownLink
		 },
		#{'Flow-Description' => [<<"permit out ip from any to assigned">>],
		  'Flow-Direction'   => [2]    %% UpLink
		 }],
	   'Metering-Method'  => [1],
	   'Precedence' => [100]
	  } || RG <- RIds],

    [RuleDef3001, RuleDef3002, RuleDef3003 | _] =
	[{group(Id), RG} || {Id, RG} <- lists:zip(RIds, RGs)],

    RuleBase1 = maps:from_list([RuleDef3001]),
    RuleBase1a = #{group(3001) => RG3001#{'Rating-Group' => [6001]}},
    RuleBase2 = maps:from_list([RuleDef3001, RuleDef3002]),
    RuleBase3 = maps:from_list([RuleDef3001, RuleDef3002, RuleDef3003,
				{rule_base(1), [group(3003)]}]),
    RuleBase3a = maps:from_list([{group(3001), RG3001#{'Rating-Group' => [6001]}},
				 RuleDef3002,
				 {group(3003), RG3003#{'Rating-Group' => [6003]}},
				 {rule_base(1), [group(3003)]}]),
    RuleBase4 = maps:from_list([RuleDef3001, RuleDef3002, RuleDef3003,
				{rule_base(1), [group(3003), group(3004)]}]),
    ct:pal("RuleBase3: ~p", [RuleBase3]),
    ct:pal("RuleBase4: ~p", [RuleBase4]),

    CRD1 = #{'Charging-Rule-Definition' => [RG3001#{'Charging-Rule-Name' => group(3001)}]},
    CRD2 = #{'Charging-Rule-Definition' => [RG3001#{'Charging-Rule-Name' => group(3001),
						    'Rating-Group' => [6001]}]},
    CRM1 = #{'Charging-Rule-Name' => [group(3002), group(3003)]},
    CRM2 = #{'Charging-Rule-Name' => [rule_base(1)]},
    CRM3 = #{'Charging-Rule-Name' => [group(3001)]},
    CRBM1 = #{'Charging-Rule-Base-Name' => [rule_base(1)]},
    CRBM2 = #{'Charging-Rule-Base-Name' => [group(3002), group(3003)]},

    %% initial requests
    Install1 = [{pcc, install, [CRD1, CRM1, CRBM1]}],
    Install1a = [{pcc, install, [CRD1]}],
    Install2 = [{pcc, install, [maps_merge([CRD1, CRM1, CRBM1])]}],
    Install3 = [{pcc, install, [CRM2, CRBM2]}],
    Install4 = [{pcc, install, [maps_merge([CRM2, CRBM2])]}],

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [3001]}}, [_|_]},
	   ergw_gsn_lib:gx_events_to_pcc_rules(Install1, #{}, #{})),
    {Rules1, _} = ergw_gsn_lib:gx_events_to_pcc_rules(Install1, #{}, #{}),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [3001]}}, [_|_]},
	   ergw_gsn_lib:gx_events_to_pcc_rules(Install2, #{}, #{})),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [3001]}}, []},
	   ergw_gsn_lib:gx_events_to_pcc_rules(Install1a, RuleBase1, #{})),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [3001]}},
	    [{not_found,<<"rb-0001">>},{not_found,<<"r-3003">>},{not_found,<<"r-3002">>}]},
	   ergw_gsn_lib:gx_events_to_pcc_rules(Install1, RuleBase1, #{})),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [3001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG},
	    [{not_found,<<"rb-0001">>},{not_found,<<"r-3003">>}]}
	       when is_map_key('Charging-Rule-Name', RG) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Install1, RuleBase2, #{})),
    {Rules2, _} = ergw_gsn_lib:gx_events_to_pcc_rules(Install1, RuleBase2, #{}),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [3001]}},
	    [{not_found,<<"r-3003">>}, {not_found,<<"r-3002">>}, {not_found,<<"rb-0001">>}]},
	   ergw_gsn_lib:gx_events_to_pcc_rules(Install2, RuleBase1, #{})),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [3001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG},
	    [{not_found,<<"r-3003">>},{not_found,<<"rb-0001">>}]}
	       when is_map_key('Charging-Rule-Name', RG) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Install2, RuleBase2, #{})),

    ?match({#{}, [_|_]}, ergw_gsn_lib:gx_events_to_pcc_rules(Install3, RuleBase1, #{})),
    ?match({#{}, [_|_]}, ergw_gsn_lib:gx_events_to_pcc_rules(Install3, RuleBase2, #{})),
    ?match({#{}, [_|_]}, ergw_gsn_lib:gx_events_to_pcc_rules(Install4, RuleBase1, #{})),
    ?match({#{}, [_|_]}, ergw_gsn_lib:gx_events_to_pcc_rules(Install4, RuleBase2, #{})),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [3001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG2,
	      <<"r-3003">> :=
		  #{'Charging-Rule-Base-Name' := <<"rb-0001">>,
		    'Rating-Group' := [3003]} = RG3},
	    []} when is_map_key('Charging-Rule-Name', RG2) =:= false andalso
		     is_map_key('Charging-Rule-Name', RG3) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Install1, RuleBase3, #{})),
    {Rules3, _} = ergw_gsn_lib:gx_events_to_pcc_rules(Install1, RuleBase3, #{}),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [3001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG2,
	      <<"r-3003">> :=
		  #{'Charging-Rule-Base-Name' := <<"rb-0001">>,
		    'Rating-Group' := [3003]} = RG3},
	   [{not_found,<<"r-3004">>}]}
	       when is_map_key('Charging-Rule-Name', RG2) =:= false andalso
		    is_map_key('Charging-Rule-Name', RG3) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Install1, RuleBase4, #{})),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [3001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG2,
	      <<"r-3003">> :=
		  #{'Charging-Rule-Base-Name' := <<"rb-0001">>,
		    'Rating-Group' := [3003]} = RG3},
	    []} when is_map_key('Charging-Rule-Name', RG2) =:= false andalso
		     is_map_key('Charging-Rule-Name', RG3) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Install2, RuleBase3, #{})),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [3001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG2,
	      <<"r-3003">> :=
		  #{'Charging-Rule-Base-Name' := <<"rb-0001">>,
		    'Rating-Group' := [3003]} = RG3},
	   [{not_found,<<"r-3004">>}]}
	       when is_map_key('Charging-Rule-Name', RG2) =:= false andalso
		    is_map_key('Charging-Rule-Name', RG3) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Install2, RuleBase4, #{})),

    ?match({#{}, [_|_]}, ergw_gsn_lib:gx_events_to_pcc_rules(Install3, RuleBase3, #{})),
    ?match({#{}, [_|_]}, ergw_gsn_lib:gx_events_to_pcc_rules(Install3, RuleBase4, #{})),
    ?match({#{}, [_|_]}, ergw_gsn_lib:gx_events_to_pcc_rules(Install4, RuleBase3, #{})),
    ?match({#{}, [_|_]}, ergw_gsn_lib:gx_events_to_pcc_rules(Install4, RuleBase4, #{})),


    %% simple update requests
    Update1 = [{pcc, install, [CRD2, CRM1, CRBM1]}],
    Update1a = [{pcc, install, [CRM3]}],
    Update2 = [{pcc, install, [maps_merge([CRD2, CRM1, CRBM1])]}],

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [6001]}}, [_|_]},
	   ergw_gsn_lib:gx_events_to_pcc_rules(Update1, RuleBase1, Rules1)),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [6001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG},
	    [{not_found,<<"rb-0001">>},{not_found,<<"r-3003">>}]}
	       when is_map_key('Charging-Rule-Name', RG) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Update1, RuleBase2, Rules1)),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [6001]}}, [_|_]},
	   ergw_gsn_lib:gx_events_to_pcc_rules(Update2, RuleBase1, Rules1)),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [6001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG},
	    [{not_found,<<"rb-0001">>}, {not_found,<<"r-3003">>}, {not_found,<<"r-3002">>}]}
	       when is_map_key('Charging-Rule-Name', RG) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Update1, RuleBase1, Rules2)),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [6001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG},
	    [{not_found,<<"r-3003">>}, {not_found,<<"r-3002">>}, {not_found,<<"rb-0001">>}]}
	       when is_map_key('Charging-Rule-Name', RG) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Update2, RuleBase1, Rules2)),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [6001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG},
	    [{not_found,<<"rb-0001">>}, {not_found,<<"r-3003">>}]}
	       when is_map_key('Charging-Rule-Name', RG) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Update1, RuleBase2, Rules2)),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [6001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG},
	    [{not_found,<<"r-3003">>}, {not_found,<<"rb-0001">>}]}
	       when is_map_key('Charging-Rule-Name', RG) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Update2, RuleBase2, Rules2)),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [6001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG}, []}
	       when is_map_key('Charging-Rule-Name', RG) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Update1a, RuleBase1a, Rules2)),

    %% update with RuleBase requests

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [6001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG2,
	      <<"r-3003">> :=
		  #{'Charging-Rule-Base-Name' := <<"rb-0001">>,
		    'Rating-Group' := [6003]} = RG3}, []}
	       when is_map_key('Charging-Rule-Name', RG2) =:= false andalso
		    is_map_key('Charging-Rule-Name', RG3) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Update1, RuleBase3a, Rules3)),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [6001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG2,
	      <<"r-3003">> :=
		  #{'Charging-Rule-Base-Name' := <<"rb-0001">>,
		    'Rating-Group' := [3003]} = RG3}, []}
	       when is_map_key('Charging-Rule-Name', RG2) =:= false andalso
		    is_map_key('Charging-Rule-Name', RG3) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Update1a, RuleBase3a, Rules3)),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [6001]},
	      <<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG2,
	      <<"r-3003">> :=
		  #{'Charging-Rule-Base-Name' := <<"rb-0001">>,
		    'Rating-Group' := [6003]} = RG3}, []}
	       when is_map_key('Charging-Rule-Name', RG2) =:= false andalso
		    is_map_key('Charging-Rule-Name', RG3) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Update2, RuleBase3a, Rules3)),

    %% simple update requests
    Remove1 = [{pcc, remove, [CRM3]}],
    Remove2 = [{pcc, remove, [maps_merge([CRM1, CRBM1])]}],
    Remove3 = [{pcc, remove, [CRM2, CRBM2]}],
    Remove4 = [{pcc, remove, [maps_merge([CRM2, CRBM2])]}],

    ?match({#{<<"r-3002">> :=
		  #{'Rating-Group' := [3002]} = RG2,
	      <<"r-3003">> :=
		  #{'Charging-Rule-Base-Name' := <<"rb-0001">>,
		    'Rating-Group' := [3003]} = RG3}, []}
	       when is_map_key('Charging-Rule-Name', RG2) =:= false andalso
		    is_map_key('Charging-Rule-Name', RG3) =:= false,
	   ergw_gsn_lib:gx_events_to_pcc_rules(Remove1, #{}, Rules3)),

    ?match({#{<<"r-3001">> :=
		  #{'Charging-Rule-Name' := <<"r-3001">>,
		    'Rating-Group' := [3001]}},
	    [{not_found,<<"r-3003">>}]},
	   ergw_gsn_lib:gx_events_to_pcc_rules(Remove2, #{}, Rules3)),

    ?match({Rules3, [{not_found,<<"rb-0001">>}]},
	   ergw_gsn_lib:gx_events_to_pcc_rules(Remove3, #{}, Rules3)),

    ?match({Rules3, [{not_found,<<"rb-0001">>}]},
	   ergw_gsn_lib:gx_events_to_pcc_rules(Remove4, #{}, Rules3)),

    ok.
