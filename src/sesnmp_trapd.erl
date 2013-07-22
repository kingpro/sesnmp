-module(sesnmp_trapd).

-include_lib("elog/include/elog.hrl").

%% User interface
-export([start_link/1, stop/0]).

%% Internal exports
-export([init/1,
		handle_call/3,
		handle_cast/2,
		handle_info/2,
		code_change/3,
		terminate/2]).

-include_lib("snmp/include/snmp_types.hrl").

-record(state, {handler, net_if, net_if_ref, net_if_opts}).

%%%-------------------------------------------------------------------
%%% API
%%%-------------------------------------------------------------------
start_link(Opts) ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [Opts], []).

stop() ->
    gen_server:call(?MODULE, stop).

init([Opts]) ->
    case (catch do_init(Opts)) of
	{ok, State} ->
        ?INFO_MSG("sesnmp trapd is started."),
	    {ok, State};
	{error, Reason} ->
	    {stop, Reason}
    end.

do_init(Opts) ->
    process_flag(trap_exit, true),
    TrapdOpts = get_opt(trapd, Opts),
    NetIfOpts = get_opt(net_if, Opts),
    Handler = get_opt(handler, TrapdOpts),
    {NetIf, NetIfRef} = do_init_net_if(TrapdOpts ++ NetIfOpts),
    {ok, #state{handler = Handler, net_if = NetIf, net_if_ref = NetIfRef, net_if_opts = NetIfOpts}}.
    
do_init_net_if(NetIfOpts) ->
    {ok, NetIf} = sesnmp_udp:start_link(self(), NetIfOpts),
    NetIfRef = erlang:monitor(process, NetIf),
    {NetIf, NetIfRef}.

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call(Req, _From, State) ->
    {stop, {badreq, Req}, State}.

handle_cast(Msg, State) ->
    {stop, {badcat, Msg}, State}.
    
handle_info({snmp_trap, Trap, Addr, Port}, State) ->
    handle_snmp_trap(Trap, Addr, Port, State),
    {noreply, State};

handle_info({'DOWN', _MonRef, process, Pid, _Reason}, 
	    #state{net_if_opts = NetIfOpts, net_if = Pid} = State) ->
    {NetIf, NetIfRef} = do_init_net_if(NetIfOpts),
    {noreply, State#state{net_if = NetIf, net_if_ref = NetIfRef}};

handle_info({snmp_error, ErrorInfo, Addr, Port}, State) ->
    ?WARNING("snmp_error from ~p:~p, error_info: ~n~p", [Addr, Port, ErrorInfo]),
    {noreply, State};

handle_info(Info, State) ->
    {stop, {badinfo, Info}, State}.

code_change(_Vsn, State, _Extra) ->
    {ok, State}.
 
terminate(_Reason, _State) ->
    ok.
    
%%----------------------------------------------------------------------
%% Retrieve user info for this agent.
%% If this is an unknown agent, then use the default user
handle_snmp_trap(#trappdu{enterprise    = Enteprise, 
			  generic_trap  = Generic, 
			  specific_trap = Spec,
			  time_stamp    = Timestamp, 
			  varbinds      = Varbinds} = Trap, 
		 Addr, Port, State) ->

    ?DEBUG("handle_snmp_trap [trappdu] -> entry with"
	    "~n   Addr: ~p"
	    "~n   Port: ~p"
	    "~n   Trap: ~p", [Addr, Port, Trap]),

    SnmpTrapInfo = {Enteprise, Generic, Spec, Timestamp, Varbinds},
    do_handle_snmp_trap(SnmpTrapInfo, Addr, Port, State);

handle_snmp_trap(#pdu{error_status = EStatus, 
		      error_index  = EIndex, 
		      varbinds     = Varbinds} = Trap, 
		 Addr, Port, State) ->

    ?DEBUG("handle_snmp_trap [pdu] -> entry with"
	    "~n   Addr: ~p"
	    "~n   Port: ~p"
	    "~n   Trap: ~p", [Addr, Port, Trap]),
    SnmpTrapInfo = {EStatus, EIndex, Varbinds},
    do_handle_snmp_trap(SnmpTrapInfo, Addr, Port, State);

handle_snmp_trap(CrapTrap, Addr, Port, _State) ->
    ?ERROR("received crap (snmp) trap from ~w:~w =>"
	      "~p", [Addr, Port, CrapTrap]),
    ok.

do_handle_snmp_trap(SnmpTrapInfo, Addr, Port, #state{handler = Mod} = _State) ->
    spawn(fun() -> 
        Mod:handle_trap(Addr, Port, SnmpTrapInfo, [])
    end).

%%----------------------------------------------------------------------
get_opt(Key, Opts) ->
    sesnmp_misc:get_option(Key, Opts).

