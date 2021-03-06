-module(lock3).
-export([init/2]).

init(MyId, Nodes) ->	%when the lock is started it is given a unique ID: MyId
	MyClock = 0,
	open(Nodes, MyId, MyClock).
		

open(Nodes, MyId, MyClock) ->
	receive
		{take, Master} ->	%my worker wants the lock
			Refs = requests(Nodes, MyId, MyClock),	%inform all other locks that i need to be taken
			wait(Nodes, Master, Refs, [], MyId, MyClock, MyClock);	%and enter waiting state MyClock twice, 1 will change the other not
		{request, From, Ref, _, Clock} ->	%request from another lock
			NewClock = lists:max([MyClock,Clock]) + 1, 
			From ! {ok, Ref, NewClock},	%immediately reply ok (i'm in open state) 
			open(Nodes, MyId, NewClock);	%and enter open state again
		stop ->
			ok
	end.
	
%sends a request message to all locks
requests(Nodes, MyId, MyClock) ->
	lists:map(fun(P) -> R = make_ref(), P ! {request, self(), R, MyId, MyClock}, R end, Nodes).	%I send my ID together with the req msg, also MyClock.

wait(Nodes, Master, [], Waiting, MyId, MyClock, _) ->	%waiting state with empty list of locks -- all of the locks sent me an ok message!! -> I can take the lock!
	Master ! taken,		%the lock is taken
	held(Nodes, Waiting, MyId, MyClock);	%enter the held state


wait(Nodes, Master, Refs, Waiting, MyId, MyClock, MyReqClock) ->	%waiting for ok messages
	receive
	%Req msg now has Req_Id and also Req_Clock to compare to it to MyReqClock
		{request, From, Ref, Req_Id, Req_Clock} ->
				NewClock = lists:max([MyClock,Req_Clock]) + 1, 
			if 
				MyReqClock > Req_Clock ->
					From ! {ok, Ref, NewClock}, %we send Ok and also the NewClock value to the other process
					wait(Nodes,Master, Refs, Waiting, MyId, NewClock, MyReqClock);
					
				MyReqClock == Req_Clock -> 
					if
					MyId < Req_Id ->	%The requesting lock has higher priority
						From ! {ok, Ref, NewClock},%send an ok message to it!	

						wait(Nodes, Master, Refs, Waiting, MyId, NewClock, MyReqClock);	%and enter waiting state
						% NOT back to open state -> back to WAIT state!!!
		
					true ->	%I have higher priority: I keep the request and I go on :p
						wait(Nodes, Master, Refs, [{From, Ref}|Waiting], MyId,NewClock, MyReqClock)
					end;
					
				true -> %% My req id is smaller
					wait(Nodes,Master, Refs, [{From,Ref}|Waiting], MyId, NewClock, MyReqClock)
			end;
		
		{ok, Ref, ReqClock2} ->	%i received an ok message from a lock
			NewClock2 = lists:max([MyClock,ReqClock2]) + 1,
			Refs2 = lists:delete(Ref, Refs),	%and I delete it from my list
			wait(Nodes, Master, Refs2, Waiting, MyId, NewClock2, MyReqClock);	%waiting for the rest of the ok messages
		
		release ->	%I have to release the lock
			ok(Waiting, MyClock),	%I sent ok messages to the locks that requested me while I was waiting
			open(Nodes, MyId, MyClock)	%back to open state
	end.

ok(Waiting, MyClock) ->	%send ok message
	lists:map(fun({F,R}) -> F ! {ok, R, MyClock} end, Waiting).

held(Nodes, Waiting, MyId, MyClock) ->	%The lock is mine!!!
	receive
		{request, From, Ref,_ ,ReqClock} ->	%I keep on accepting requests from other locks to send them ok afterwards
			NewClock = lists:max([MyClock,ReqClock]) + 1,
			held(Nodes, [{From, Ref}|Waiting], MyId, NewClock );
		release ->	%release message from the worker -> I have to release the lock
			ok(Waiting, MyClock),			%I inform the waiting locks!
			open(Nodes, MyId, MyClock)	%back to open state!!
	end.
