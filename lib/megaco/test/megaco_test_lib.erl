%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 1999-2009. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%
%%

%%
%%----------------------------------------------------------------------
%% Purpose: Lightweight test server
%%----------------------------------------------------------------------

-module(megaco_test_lib).

-compile(export_all).

-include("megaco_test_lib.hrl").


%% ----------------------------------------------------------------
%% Time related function
%%

sleep(infinity) ->
    receive
    after infinity ->
            ok
    end;
sleep(MSecs) ->
    receive
    after trunc(MSecs) ->
            ok
    end,
    ok.


hours(N)   -> trunc(N * 1000 * 60 * 60).
minutes(N) -> trunc(N * 1000 * 60).
seconds(N) -> trunc(N * 1000).


%% ----------------------------------------------------------------
%% Conditional skip of testcases
%%

non_pc_tc_maybe_skip(Config, Condition, File, Line) 
  when is_list(Config) andalso is_function(Condition) ->
    %% Check if we shall skip the skip
    case os:getenv("TS_OS_BASED_SKIP") of
	"false" ->
	    ok;
	_ ->
	    case lists:keysearch(ts, 1, Config) of
		{value, {ts, megaco}} ->
		    %% Always run the testcase if we are using our own 
		    %% test-server...
		    ok;
		_ ->
		    case (catch Condition()) of
			true ->
			    skip(non_pc_testcase, File, Line);
			_ ->
			    ok
		    end
	    end
    end.


os_based_skip(any) ->
    true;
os_based_skip(Skippable) when is_list(Skippable) ->
    {OsFam, OsName} = 
	case os:type() of
	    {_Fam, _Name} = FamAndName ->
		FamAndName;
	    Fam ->
		{Fam, undefined}
	end,
    case lists:member(OsFam, Skippable) of
	true ->
	    true;
	false ->
	    case lists:keysearch(OsFam, 1, Skippable) of
		{value, {OsFam, OsName}} ->
		    true;
		{value, {OsFam, OsNames}} when is_list(OsNames) ->
		    lists:member(OsName, OsNames);
		_ ->
		    false
	    end
    end;
os_based_skip(_) ->
    false.
    
	    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Evaluates a test case or test suite
%% Returns a list of failing test cases:
%% 
%%     {Mod, Fun, ExpectedRes, ActualRes}
%%----------------------------------------------------------------------

tickets(Case) ->
    Res = lists:flatten(tickets(Case, default_config())),
    %% io:format("Res: ~p~n", [Res]),
    display_result(Res),
    Res.

tickets(Cases, Config) when is_list(Cases) ->     
    [tickets(Case, Config) || Case <- Cases];
tickets(Mod, Config) when is_atom(Mod) ->
    Res = tickets(Mod, tickets, Config),
    Res;
tickets(Bad, _Config) ->
    [{badarg, Bad, ok}].

tickets(Mod, Func, Config) ->
    case (catch Mod:Func(suite)) of
	[] ->
	    io:format("Eval:   ~p:", [{Mod, Func}]),
	    Res = eval(Mod, Func, Config),
	    {R, _, _} = Res,
	    io:format(" ~p~n", [R]),
	    Res;
	
	Cases when is_list(Cases) ->
	    io:format("Expand: ~p:~p ... ~n"
		      "        ~p~n", [Mod, Func, Cases]),
	    Map = fun({M,_}) when is_atom(M) -> 
			  tickets(M, tickets, Config);
		     (F)     when is_atom(F) -> 
			  tickets(Mod, F, Config);
		     (Case) -> Case
		  end,
	    lists:map(Map, Cases);

        {req, _, {conf, Init, Cases, Finish}} ->
	    case (catch Mod:Init(Config)) of
		Conf when is_list(Conf) ->
		    io:format("Expand: ~p:~p ...~n", [Mod, Func]),
		    Map = fun({M,_}) when is_atom(M) -> 
				  tickets(M, tickets, Config);
			     (F)     when is_atom(F) -> 
				  tickets(Mod, F, Config);
			     (Case) -> Case
			  end,
		    Res = lists:map(Map, Cases),
		    (catch Mod:Finish(Conf)),
		    Res;
		    
		{'EXIT', {skipped, Reason}} ->
		    io:format(" => skipping: ~p~n", [Reason]),
		    [{skipped, {Mod, Func}, Reason}];
		    
		Error ->
		    io:format(" => init failed: ~p~n", [Error]),
		    [{failed, {Mod, Func}, Error}]
	    end;
		    
        {'EXIT', {undef, _}} ->
	    io:format("Undefined:   ~p~n", [{Mod, Func}]),
	    [{nyi, {Mod, Func}, ok}];
		    
        Error ->
	    io:format("Ignoring:   ~p:~p: ~p~n", [Mod, Func, Error]),
	    [{failed, {Mod, Func}, Error}]
    end.
	

display_alloc_info() ->
    io:format("Allocator memory information:~n", []),
    AllocInfo = alloc_info(),
    display_alloc_info(AllocInfo).

display_alloc_info([]) ->
    ok;
display_alloc_info([{Alloc, Mem}|AllocInfo]) ->
    io:format("  ~15w: ~10w~n", [Alloc, Mem]),
    display_alloc_info(AllocInfo).
    
alloc_info() ->
    case erlang:system_info(allocator) of
	{_Allocator, _Version, Features, _Settings} ->
	    alloc_info(Features);
	_ ->
	    []
    end.

alloc_info(Allocators) ->
    Allocs = [temp_alloc, sl_alloc, std_alloc, ll_alloc, eheap_alloc, 
	      ets_alloc, binary_alloc, driver_alloc], 
    alloc_info(Allocators, Allocs, []).

alloc_info([], _, Acc) ->
    lists:reverse(Acc);
alloc_info([Allocator | Allocators], Allocs, Acc) ->
    case lists:member(Allocator, Allocs) of
	true ->
	    Instances0 = erlang:system_info({allocator, Allocator}),
	    Instances = 
		if 
		    is_list(Instances0) ->
			[Instance || Instance <- Instances0, 
				     element(1, Instance) =:= instance];
		    true ->
			[]
		end,
	    AllocatorMem = alloc_mem_info(Instances),
	    alloc_info(Allocators, Allocs, [{Allocator, AllocatorMem} | Acc]);

	false ->
	    alloc_info(Allocators, Allocs, Acc)
    end.
    
alloc_mem_info(Instances) ->
    alloc_mem_info(Instances, []).

alloc_mem_info([], Acc) ->
    lists:sum([Mem || {instance, _, Mem} <- Acc]);
alloc_mem_info([{instance, N, Info}|Instances], Acc) ->
    InstanceMemInfo = alloc_instance_mem_info(Info),
    alloc_mem_info(Instances, [{instance, N, InstanceMemInfo} | Acc]).

alloc_instance_mem_info(InstanceInfo) ->
    MBCS = alloc_instance_mem_info(mbcs, InstanceInfo),
    SBCS = alloc_instance_mem_info(sbcs, InstanceInfo),
    MBCS + SBCS.

alloc_instance_mem_info(Key, InstanceInfo) ->
    case lists:keysearch(Key, 1, InstanceInfo) of
	{value, {Key, Info}} ->
	    case lists:keysearch(blocks_size, 1, Info) of
		{value, {blocks_size, Mem, _, _}} ->
		    Mem;
		_ ->
		    0
	    end;
	_ ->
	    0
    end.
		      
    
t(Case) ->
    process_flag(trap_exit, true),
    MEM = fun() -> case (catch erlang:memory()) of
			{'EXIT', _} ->
			    [];
			Res ->
			    Res
		    end
	  end,
    Alloc1 = alloc_info(),
    Mem1 = MEM(),
    Res  = lists:flatten(t(Case, default_config())),
    Alloc2 = alloc_info(),
    Mem2 = MEM(),
    %% io:format("Res: ~p~n", [Res]),
    display_result(Res, Alloc1, Mem1, Alloc2, Mem2),
    Res.

t({Mod, Fun}, Config) when is_atom(Mod) andalso is_atom(Fun) ->
    case catch apply(Mod, Fun, [suite]) of
	[] ->
	    io:format("Eval:   ~p:", [{Mod, Fun}]),
	    Res = eval(Mod, Fun, Config),
	    {R, _, _, _} = Res,
	    io:format(" ~p~n", [R]),
	    Res;

	Cases when is_list(Cases) ->
	    io:format("Expand: ~p ...~n", [{Mod, Fun}]),
	    Map = fun(Case) when is_atom(Case) -> {Mod, Case};
		     (Case) -> Case
		  end,
	    t(lists:map(Map, Cases), Config);

        {req, _, {conf, Init, Cases, Finish}} ->
	    case (catch apply(Mod, Init, [Config])) of
		Conf when is_list(Conf) ->
		    io:format("Expand: ~p ...~n", [{Mod, Fun}]),
		    Map = fun(Case) when is_atom(Case) -> {Mod, Case};
			     (Case) -> Case
			  end,
		    Res = t(lists:map(Map, Cases), Conf),
		    (catch apply(Mod, Finish, [Conf])),
		    Res;
		    
		{'EXIT', {skipped, Reason}} ->
		    io:format(" => skipping: ~p~n", [Reason]),
		    [{skipped, {Mod, Fun}, Reason, 0}];
		    
		Error ->
		    io:format(" => failed: ~p~n", [Error]),
		    [{failed, {Mod, Fun}, Error, 0}]
	    end;
		    
        {'EXIT', {undef, _}} ->
	    io:format("Undefined:   ~p~n", [{Mod, Fun}]),
	    [{nyi, {Mod, Fun}, ok, 0}];
		    
        Error ->
	    io:format("Ignoring:   ~p: ~p~n", [{Mod, Fun}, Error]),
	    [{failed, {Mod, Fun}, Error, 0}]
    end;
t(Mod, Config) when is_atom(Mod) ->
    Res = t({Mod, all}, Config),
    Res;
t(Cases, Config) when is_list(Cases) ->
    [t(Case, Config) || Case <- Cases];
t(Bad, _Config) ->
    [{badarg, Bad, ok, 0}].

eval(Mod, Fun, Config) ->
    TestCase = {?MODULE, Mod, Fun},
    Label = lists:concat(["TEST CASE: ", Fun]),
    megaco:report_event(40, ?MODULE, Mod, Label ++ " started",
			[TestCase, Config]),
    global:register_name(megaco_test_case_sup, self()),
    Flag = process_flag(trap_exit, true),
    put(megaco_test_server, true),
    Config2 = Mod:init_per_testcase(Fun, Config),
    Pid = spawn_link(?MODULE, do_eval, [self(), Mod, Fun, Config2]),
    R = wait_for_evaluator(Pid, Mod, Fun, Config2, []),
    Mod:fin_per_testcase(Fun, Config2),
    erase(megaco_test_server),    
    global:unregister_name(megaco_test_case_sup),
    process_flag(trap_exit, Flag),
    R.

-record('REASON', {mod, line, desc}).

wait_for_evaluator(Pid, Mod, Fun, Config, Errors) ->
    wait_for_evaluator(Pid, Mod, Fun, Config, Errors, 0).
wait_for_evaluator(Pid, Mod, Fun, Config, Errors, AccTime) ->
    TestCase = {?MODULE, Mod, Fun},
    Label = lists:concat(["TEST CASE: ", Fun]),
    receive
	{done, Pid, ok, Time} when Errors =:= [] ->
	    megaco:report_event(40, Mod, ?MODULE, Label ++ " ok",
				[TestCase, Config]),
	    {ok, {Mod, Fun}, Errors, Time};
	{done, Pid, ok, Time} ->
	    megaco:report_event(40, Mod, ?MODULE, Label ++ " failed",
				[TestCase, Config]),
	    {failed, {Mod, Fun}, Errors, Time};
	{done, Pid, {ok, _}, Time} when Errors =:= [] ->
	    megaco:report_event(40, Mod, ?MODULE, Label ++ " ok",
				[TestCase, Config]),
	    {ok, {Mod, Fun}, Errors, Time};
	{done, Pid, {ok, _}, Time} ->
	    megaco:report_event(40, Mod, ?MODULE, Label ++ " failed",
				[TestCase, Config]),
	    {failed, {Mod, Fun}, Errors, Time};
	{done, Pid, Fail, Time} ->
	    megaco:report_event(20, Mod, ?MODULE, Label ++ " failed",
				[TestCase, Config, {return, Fail}, Errors]),
	    {failed, {Mod,Fun}, Fail, Time};
	{'EXIT', Pid, {skipped, Reason}, Time} -> 
	    megaco:report_event(20, Mod, ?MODULE, Label ++ " skipped",
				[TestCase, Config, {skipped, Reason}]),
	    {skipped, {Mod, Fun}, Errors, Time};
	{'EXIT', Pid, Reason, Time} -> 
	    megaco:report_event(20, Mod, ?MODULE, Label ++ " crashed",
				[TestCase, Config, {'EXIT', Reason}]),
	    {crashed, {Mod, Fun}, [{'EXIT', Reason} | Errors], Time};
	{fail, Pid, Reason, Time} ->
	    wait_for_evaluator(Pid, Mod, Fun, Config, 
			       Errors ++ [Reason], AccTime + Time)
    end.

do_eval(ReplyTo, Mod, Fun, Config) ->
    display_system_info("before", Mod, Fun),
    case timer:tc(Mod, Fun, [Config]) of
	{Time, {'EXIT', {skipped, Reason}}} ->
	    display_tc_time(Time),
	    display_system_info("after (skipped)", Mod, Fun),
	    ReplyTo ! {'EXIT', self(), {skipped, Reason}, Time};
	{Time, Other} ->
	    display_tc_time(Time),
	    display_system_info("after", Mod, Fun),
	    ReplyTo ! {done, self(), Other, Time}
    end,
    unlink(ReplyTo),
    exit(shutdown).


display_tc_time(Time) ->
    io:format("~n"
	      "~n*********************************************"
	      "~n"
	      "~nTest case completion time: ~.3f sec (~w)"
	      "~n", [(Time / 1000000), Time]),
    ok.

display_system_info(WhenStr) ->
    display_system_info(WhenStr, undefined, undefined).

display_system_info(WhenStr, undefined, undefined) ->
    display_system_info(WhenStr, "");
display_system_info(WhenStr, Mod, Func) ->
    ModFuncStr = lists:flatten(io_lib:format(" ~w:~w", [Mod, Func])),
    display_system_info(WhenStr, ModFuncStr).

display_system_info(WhenStr, ModFuncStr) ->
    Fun = fun(F) -> case (catch F()) of
			{'EXIT', _} ->
			    undefined;
			Res ->
			    Res
		    end
	  end,
    ProcCount    = Fun(fun() -> erlang:system_info(process_count) end),
    ProcLimit    = Fun(fun() -> erlang:system_info(process_limit) end),
    ProcMemAlloc = Fun(fun() -> erlang:memory(processes) end),
    ProcMemUsed  = Fun(fun() -> erlang:memory(processes_used) end),
    ProcMemBin   = Fun(fun() -> erlang:memory(binary) end),
    ProcMemTot   = Fun(fun() -> erlang:memory(total) end),
    %% error_logger:info_msg(
    io:format("~n"
	      "~n*********************************************"
	      "~n"
	      "System info ~s~s => "
	      "~n   Process count:        ~w"
              "~n   Process limit:        ~w"
              "~n   Process memory alloc: ~w"
              "~n   Process memory used:  ~w"
              "~n   Memory for binaries:  ~w"
              "~n   Memory total:         ~w"
	      "~n"
	      "~n*********************************************"
	      "~n"
	      "~n", [WhenStr, ModFuncStr, 
		     ProcCount, ProcLimit, ProcMemAlloc, ProcMemUsed, 
		     ProcMemBin, ProcMemTot]),
    ok.

display_result(Res, Alloc1, Mem1, Alloc2, Mem2) ->
    io:format("~nAllocator info: ~n", []),
    display_alloc(Alloc1, Alloc2),
    io:format("~nMemory info: ~n", []),
    display_memory(Mem1, Mem2),
    display_result(Res).

display_alloc([], []) ->
    io:format("-~n", []),
    ok;
display_alloc(A1, A2) ->
    do_display_alloc(A1, A2).

do_display_alloc([], _) ->
    ok;
do_display_alloc([{Alloc, Mem1}|AllocInfo1], AllocInfo2) ->
    Mem2 = 
	case lists:keysearch(Alloc, 1, AllocInfo2) of
	    {value, {_, Val}} ->
		Val;
	    false ->
		undefined
	end,
    io:format("~15w: ~10w -> ~w~n", [Alloc, Mem1, Mem2]),
    do_display_alloc(AllocInfo1, AllocInfo2).

display_memory([], []) ->
    io:format("-~n", []),
    ok;
display_memory(Mem1, Mem2) ->
    do_display_memory(Mem1, Mem2).


do_display_memory([], _) ->
    ok;
do_display_memory([{Key, Mem1}|MemInfo1], MemInfo2) ->
    Mem2 = 
	case lists:keysearch(Key, 1, MemInfo2) of
	    {value, {_, Val}} ->
		Val;
	    false ->
		undefined
	end,
    io:format("~15w: ~10w -> ~w~n", [Key, Mem1, Mem2]),
    do_display_memory(MemInfo1, MemInfo2).

display_result([]) ->    
    io:format("OK~n", []);
display_result(Res) when is_list(Res) ->
    Ok      = [{MF, Time} || {ok,  MF, _, Time}  <- Res],
    Nyi     = [MF || {nyi, MF, _, _Time} <- Res],
    Skipped = [{MF, Reason} || {skipped, MF, Reason, _Time} <- Res],
    Failed  = [{MF, Reason} || {failed,  MF, Reason, _Time} <- Res],
    Crashed = [{MF, Reason} || {crashed, MF, Reason, _Time} <- Res],
    display_summery(Ok, Nyi, Skipped, Failed, Crashed),
    display_ok(Ok),
    display_skipped(Skipped),
    display_failed(Failed),
    display_crashed(Crashed).

display_summery(Ok, Nyi, Skipped, Failed, Crashed) ->
    io:format("~nTest case summery:~n", []),
    display_summery(Ok,      "successfull"),
    display_summery(Nyi,     "not yet implemented"),
    display_summery(Skipped, "skipped"),
    display_summery(Failed,  "failed"),
    display_summery(Crashed, "crashed"),
    io:format("~n", []).
   
display_summery(Res, Info) ->
    io:format("  ~w test cases ~s~n", [length(Res), Info]).
    
display_ok([]) ->
    ok;
display_ok(Ok) ->
    io:format("Ok test cases:~n", []),
    F = fun({{M, F}, Time}) -> 
		io:format("  ~w : ~w => ~.2f sec~n", [M, F, Time / 1000000]) 
	end,
    lists:foreach(F, Ok),
    io:format("~n", []).

display_skipped([]) ->
    ok;
display_skipped(Skipped) ->
    io:format("Skipped test cases:~n", []),
    F = fun({MF, Reason}) -> io:format("  ~p => ~p~n", [MF, Reason]) end,
    lists:foreach(F, Skipped),
    io:format("~n", []).


display_failed([]) ->
    ok;
display_failed(Failed) ->
    io:format("Failed test cases:~n", []),
    F = fun({MF, Reason}) -> io:format("  ~p => ~p~n", [MF, Reason]) end,
    lists:foreach(F, Failed),
    io:format("~n", []).

display_crashed([]) ->
    ok;
display_crashed(Crashed) ->
    io:format("Crashed test cases:~n", []),
    F = fun({MF, Reason}) -> io:format("  ~p => ~p~n", [MF, Reason]) end,
    lists:foreach(F, Crashed),
    io:format("~n", []).
        
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Verify that the actual result of a test case matches the exected one
%% Returns the actual result
%% Stores the result in the process dictionary if mismatch

error(Actual, Mod, Line) ->
    global:send(megaco_global_logger, {failed, Mod, Line}),
    log("<ERROR> Bad result: ~p~n", [Actual], Mod, Line),
    Label = lists:concat([Mod, "(", Line, ") unexpected result"]),
    megaco:report_event(60, Mod, Mod, Label,
			[{line, Mod, Line}, {error, Actual}]),
    case global:whereis_name(megaco_test_case_sup) of
	undefined -> 
	    ignore;
	Pid -> 
	    Fail = #'REASON'{mod = Mod, line = Line, desc = Actual},
	    Pid ! {fail, self(), Fail}
    end,
    Actual.

log(Format, Args, Mod, Line) ->
    case global:whereis_name(megaco_global_logger) of
	undefined ->
	    io:format(user, "~p~p(~p): " ++ Format, 
		      [self(), Mod, Line] ++ Args);
	Pid ->
	    io:format(Pid, "~p~p(~p): " ++ Format, 
		      [self(), Mod, Line] ++ Args)
    end.

skip(Actual, File, Line) ->
    log("Skipping test case~n", [], File, Line),
    String = lists:flatten(io_lib:format("Skipping test case ~p(~p): ~p~n",
					 [File, Line, Actual])),
    exit({skipped, String}).

fatal_skip(Actual, File, Line) ->
    error(Actual, File, Line),
    exit(shutdown).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Flush the message queue and return its messages
flush() ->
    receive
	Msg ->
	    [Msg | flush()]
    after 1000 ->
	    []
    end.
	    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Check if process is alive and kicking
still_alive(Pid) ->   
    case catch erlang:is_process_alive(Pid) of % New BIF in Erlang/OTP R5
	true -> 
	    true;
	false -> 
	    false;
	{'EXIT', _} -> % Pre R5 backward compatibility 
	    case process_info(Pid, message_queue_len) of
		undefined -> false;
		_ -> true
	    end 
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% The proxy process

proxy_start(ProxyId) ->
    spawn_link(?MODULE, proxy_init, [ProxyId, self()]).

proxy_start(Node, ProxyId) ->
    spawn_link(Node, ?MODULE, proxy_init, [ProxyId, self()]).

proxy_init(ProxyId, Controller) ->
    process_flag(trap_exit, true),
    ?LOG("[~p] proxy started by ~p~n",[ProxyId, Controller]),
    proxy_loop(ProxyId, Controller).

proxy_loop(OwnId, Controller) ->
    receive
	{'EXIT', Controller, Reason} ->
	    p("proxy_loop -> received exit from controller"
	      "~n   Reason: ~p"
	      "~n", [Reason]),
	    exit(Reason);
	{apply, Fun} ->
	    p("proxy_loop -> received apply request~n", []),
	    Res = Fun(),
	    p("proxy_loop -> apply result: "
	      "~n   ~p"
	      "~n", [Res]),
	    Controller ! {res, OwnId, Res},
	    proxy_loop(OwnId, Controller);
	OtherMsg ->
	    p("proxy_loop -> received unknown message: "
	      "~n  OtherMsg: ~p"
	      "~n", [OtherMsg]),
	    Controller ! {msg, OwnId, OtherMsg},
	    proxy_loop(OwnId, Controller)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Test server callbacks
init_per_testcase(_Case, Config) ->
    Pid = group_leader(),
    Name = megaco_global_logger,
    case global:whereis_name(Name) of
	undefined ->
	    global:register_name(megaco_global_logger, Pid);
	Pid ->
	    io:format("~w:init_per_testcase -> "
		      "already registered to ~p~n", [?MODULE, Pid]),
	    ok;
	OtherPid when is_pid(OtherPid) ->
	    io:format("~w:init_per_testcase -> "
		      "already registered to other ~p (~p)~n", 
		      [?MODULE, OtherPid, Pid]),
	    exit({already_registered, {megaco_global_logger, OtherPid, Pid}})
    end,
    set_kill_timer(Config).

fin_per_testcase(_Case, Config) ->
    Name = megaco_global_logger,
    case global:whereis_name(Name) of
	undefined ->
	    io:format("~w:fin_per_testcase -> already un-registered~n", 
		      [?MODULE]),
	    ok;
	Pid when is_pid(Pid) ->
	    global:unregister_name(megaco_global_logger),
	    ok
    end,
    reset_kill_timer(Config).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Set kill timer

set_kill_timer(Config) ->
    case init:get_argument(megaco_test_timeout) of
	{ok, _} -> 
	    Config;
	_ ->
	    Time = 
		case lookup_config(tc_timeout, Config) of
		    [] ->
			timer:minutes(5);
		    ConfigTime when is_integer(ConfigTime) ->
			ConfigTime
		end,
	    Dog = 
		case get(megaco_test_server) of
		    true ->
			spawn_link(?MODULE, watchdog, [self(), Time]);
		    _ ->
			test_server:timetrap(Time)
		end,
	    [{kill_timer, Dog}|Config]
		    
	    
    end.

reset_kill_timer(Config) ->
    DogKiller = 
	case get(megaco_test_server) of
	    true ->
		fun(P) when is_pid(P) -> P ! stop;
		   (_) -> ok 
		end;
	    _ ->
		fun(Ref) -> test_server:timetrap_cancel(Ref) end
	end,
    case lists:keysearch(kill_timer, 1, Config) of
	{value, {kill_timer, Dog}} ->
	    DogKiller(Dog), 
	    lists:keydelete(kill_timer, 1, Config);
	_ ->
	    Config
    end.

watchdog(Pid, Time) ->
    erlang:now(),
    receive
	stop ->
	    ok
    after Time ->
	    case (catch process_info(Pid)) of
		undefined ->
		    ok;
		Info ->
		    ?LOG("<ERROR> Watchdog in test case timed out "
			"for ~p after ~p min"
			 "~n~p"
			 "~n",
		    [Pid, Time div (1000*60), Info]),
		    exit(Pid, kill)
	    end
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

prepare_test_case(Actions, N, Config, File, Line) ->
    OrigNodes = lookup_config(nodes, Config),
    TestNodes = lookup_config(nodenames, Config), %% For testserver
    This = node(),
    SomeNodes = OrigNodes ++ (TestNodes -- OrigNodes),
    AllNodes = [This | (SomeNodes -- [This])],
    Nodes = pick_n_nodes(N, AllNodes, File, Line),
    start_nodes(Nodes, File, Line),
    do_prepare_test_case(Actions, Nodes, Config, File, Line).

do_prepare_test_case([init | Actions], Nodes, Config, File, Line) ->
    process_flag(trap_exit, true),
    megaco_test_lib:flush(),
    do_prepare_test_case(Actions, Nodes, Config, File, Line);
do_prepare_test_case([{stop_app, App} | Actions], Nodes, Config, File, Line) ->
    _Res = rpc:multicall(Nodes, application, stop, [App]),
    do_prepare_test_case(Actions, Nodes, Config, File, Line);
do_prepare_test_case([], Nodes, _Config, _File, _Line) ->
    Nodes.

pick_n_nodes(all, AllNodes, _File, _Line) ->
    AllNodes;
pick_n_nodes(N, AllNodes, _File, _Line) 
  when is_integer(N) andalso (length(AllNodes) >= N) ->
    AllNodes -- lists:nthtail(N, AllNodes);
pick_n_nodes(N, AllNodes, File, Line) ->
    fatal_skip({too_few_nodes, N, AllNodes}, File, Line).
   
lookup_config(Key,Config) ->
    case lists:keysearch(Key, 1, Config) of
	{value,{Key,Val}} ->
	    Val;
	_ ->
	    []
    end.

default_config() ->
    [{nodes, default_nodes()}, {ts, megaco}].

default_nodes() ->    
    mk_nodes(2, []).

mk_nodes(0, Nodes) ->
    Nodes;
mk_nodes(N, []) ->
    mk_nodes(N - 1, [node()]);
mk_nodes(N, Nodes) when N > 0 ->
    Head = hd(Nodes),
    [Name, Host] = node_to_name_and_host(Head),
    Nodes ++ [mk_node(I, Name, Host) || I <- lists:seq(1, N)].

mk_node(N, Name, Host) ->
    list_to_atom(lists:concat([Name ++ integer_to_list(N) ++ "@" ++ Host])).
    
%% Returns [Name, Host]    
node_to_name_and_host(Node) ->
    string:tokens(atom_to_list(Node), [$@]).

start_nodes([Node | Nodes], File, Line) ->
    case net_adm:ping(Node) of
	pong ->
	    start_nodes(Nodes, File, Line);
	pang ->
	    [Name, Host] = node_to_name_and_host(Node),
	    case slave:start_link(Host, Name) of
		{ok, NewNode} when NewNode =:= Node ->
		    Path = code:get_path(),
		    {ok, Cwd} = file:get_cwd(),
		    true = rpc:call(Node, code, set_path, [Path]),
		    ok = rpc:call(Node, file, set_cwd, [Cwd]),
		    true = rpc:call(Node, code, set_path, [Path]),
		    {_, []} = rpc:multicall(global, sync, []),
		    start_nodes(Nodes, File, Line);
		Other ->
		    fatal_skip({cannot_start_node, Node, Other}, File, Line)
	    end
    end;
start_nodes([], _File, _Line) ->
    ok.

p(F,A) ->
    io:format("~p" ++ F ++ "~n", [self()|A]).
