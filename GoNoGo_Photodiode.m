clear; clc;
KbName('UnifyKeyNames');

%% Parameters
nTrials = 50;              
stimDuration = 2.0;         
isi = 3.0;                  
fixationDuration = 0.8;     
escapeKey = KbName('ESCAPE');

Screen('Preference', 'SkipSyncTests', 1);  
Screen('Preference', 'VisualDebugLevel', 0);
Screen('Preference', 'ConserveVRAM', 64);

%% --- BioSemi Trigger Setup ---
baudRate = 115200;
dataBits = 8;
stopBits = 1;
parity = 'none';
pulseWidthSec = 0.01;

trig.enable = true;
trig.port = 'COM9';
trig.usb = [];

try
    if trig.enable
        trig.usb = serial(trig.port,'BaudRate',baudRate,'DataBits',dataBits,...
            'StopBits',stopBits,'Parity',parity,'FlowControl','none');
        fopen(trig.usb);
        fwrite(trig.usb,0);
        WaitSecs(pulseWidthSec);
    end
catch
    warning('Trigger port NOT opened.');
    trig.enable = false;
end

%% Trigger helper functions
sendTrig     = @(code) sendPulseMs(trig, code, pulseWidthSec);
sendRespOn   = @(code) sendPulseArm(trig, code);
sendRespOff  = @(      ) sendPulseClear(trig);

%% Trigger codes
FIX_CODE               = 5;  
STIM_CODE_GO_FREQ      = 10;  
STIM_CODE_GO_INFREQ    = 20;  
STIM_CODE_NOGO         = 30;  
RESP_CODE_PRESS        = 40;  
RESP_CODE_NO_PRESS     = 50;
ESC_CODE               = 255;

%% Create randomized trial sequence
nFreqGo   = round(0.65 * nTrials);
nInfreqGo = round(0.05 * nTrials);
nNoGo     = nTrials - nFreqGo - nInfreqGo;

trialTypes = [repmat(STIM_CODE_GO_FREQ,1,nFreqGo), ...
              repmat(STIM_CODE_GO_INFREQ,1,nInfreqGo), ...
              repmat(STIM_CODE_NOGO,1,nNoGo)];
trialTypes = trialTypes(randperm(nTrials));  

%% Screen setup
screenNumber = max(Screen('Screens'));
[win, winRect] = PsychImaging('OpenWindow', screenNumber, 0);
Screen('TextSize', win, 80);
[xCenter,yCenter] = RectCenter(winRect);
HideCursor;

%% --- Photodiode Setup (BOTTOM RIGHT) ---
pdSize = 60;
pdRect = [winRect(3)-pdSize  winRect(4)-pdSize ...
          winRect(3)         winRect(4)];
pdColorOn  = [255 255 255];
pdColorOff = [0 0 0];

%% Instructions
DrawFormattedText(win, ...
    'Respond to GREEN (Frequent Go) or BLUE (Infrequent Go) circles\nDo NOT respond to RED circles (No-Go)\n\nPress ESC to exit\n\nPress any key to start', ...
    'center','center',[255 255 255]);
Screen('Flip', win);
KbStrokeWait;

%% Results structure
results = struct('trialNum',{},'stimCode',{},'pressOnset',{},'releaseTime',{},'pressDur',{},...
                 'stimOnsetTime',{},'isiOnsetTime',{},'fixOnsetTime',{});

exitFlag = false;

%% ================= TRIAL LOOP =================
for t = 1:nTrials
    if exitFlag, break; end

    %% --- Fixation ---
    fixCrossDim = 40; lineWidth = 6;
    xCoords = [-fixCrossDim fixCrossDim 0 0];
    yCoords = [0 0 -fixCrossDim fixCrossDim];
    allCoords = [xCoords; yCoords];
    Screen('DrawLines',win,allCoords,lineWidth,[255 255 255],[xCenter yCenter]);
    Screen('FillRect', win, pdColorOff, pdRect); % diode OFF during fixation
    fixOnset = Screen('Flip', win);
    sendTrig(FIX_CODE);
    WaitSecs(fixationDuration);

    %% --- Prepare stimulus ---
    stimCode = trialTypes(t);
    Screen('FillRect', win, 0);

    circleRadius = 100;
    circleRect = CenterRectOnPointd([0 0 circleRadius*2 circleRadius*2], xCenter, yCenter);

    switch stimCode
        case STIM_CODE_GO_FREQ
            color = [0 255 0];
        case STIM_CODE_GO_INFREQ
            color = [0 0 255];
        case STIM_CODE_NOGO
            color = [255 0 0];
    end

    Screen('FillOval', win, color, circleRect);

    % ---- PHOTODIODE ON (same frame as stimulus) ----
    Screen('FillRect', win, pdColorOn, pdRect);

    %% --- Stimulus onset ---
    stimOnset = Screen('Flip', win);
    sendTrig(stimCode);

    %% --- Response collection ---
    pressOnsets = [];
    releaseTimes = [];
    durations = [];
    isPressing = false;
    stimEnd = stimOnset + stimDuration;

    while GetSecs < stimEnd
        [keyIsDown, secs, keyCode] = KbCheck;

        if keyIsDown && keyCode(escapeKey)
            sendTrig(ESC_CODE);
            exitFlag = true;
            break;
        end

        if keyIsDown
            if ~isPressing
                isPressing = true;
                pressOnsets(end+1) = secs;
                sendRespOn(RESP_CODE_PRESS);

                % ---- Clear stimulus immediately ----
                Screen('FillRect', win, 0);
                Screen('FillRect', win, pdColorOff, pdRect);
                Screen('Flip', win);
                break;
            end
        else
            if isPressing
                isPressing = false;
                releaseTimes(end+1) = secs;
                durations(end+1) = releaseTimes(end) - pressOnsets(end);
                sendRespOff();
            end
        end
    end

    % If stimulus ended without press
    if ~isPressing
        Screen('FillRect', win, 0);
        Screen('FillRect', win, pdColorOff, pdRect);
        stimOffset = Screen('Flip', win);
    else
        stimOffset = GetSecs;
    end

    if isempty(pressOnsets)
        sendRespOn(RESP_CODE_NO_PRESS);
        WaitSecs(0.01);
        sendRespOff();
    end

    %% --- ISI ---
    isiOnset = stimOffset;
    WaitSecs(isi);

    %% --- Save trial ---
    results(t).trialNum = t;
    results(t).stimCode = stimCode;
    results(t).pressOnset = pressOnsets - stimOnset;
    results(t).releaseTime = releaseTimes - stimOnset;
    results(t).pressDur = durations;
    results(t).stimOnsetTime = stimOnset;
    results(t).isiOnsetTime = isiOnset;
    results(t).fixOnsetTime = fixOnset;
end

%% --- End screen ---
ShowCursor;
DrawFormattedText(win,'Task complete!\n\nPress any key to exit.',...
    'center','center',[255 255 255]);
Screen('Flip', win);
KbStrokeWait;
sca;

%% Close trigger port
if trig.enable && ~isempty(trig.usb)
    fwrite(trig.usb,0);
    fclose(trig.usb);
    delete(trig.usb);
end

%% Save results
timestamp = datestr(now,'yyyymmdd_HHMMSS');
filename = ['gonogo_100trials_allPresses_' timestamp '.mat'];
save(filename,'results');
disp(['Data saved to ' filename]);

%% ================= Helper functions ===========================
function sendPulseMs(trig, value, holdSec)
    if ~trig.enable || isempty(trig.usb), return; end
    fwrite(trig.usb,value);
    WaitSecs(holdSec);
    fwrite(trig.usb,0);
end

function sendPulseArm(trig, value)
    if ~trig.enable || isempty(trig.usb), return; end
    fwrite(trig.usb,value);  
end

function sendPulseClear(trig)
    if ~trig.enable || isempty(trig.usb), return; end
    fwrite(trig.usb,0);      
end
