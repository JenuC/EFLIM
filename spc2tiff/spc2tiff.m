% This script converts Becker & Hickl .spc FIFO files to photon-arrival 
% .tif image stacks.
%
% '.spc' --> '.tif'
% The .spc file contains the photon stream and the line clocks
%
%ELiiiiiii, 20240407, initial version
%ELiiiiiii, 20240621, add parameters && disp flag && photon averaging
%ELiiiiiii, 20260212, code cleanup and enhanced comments

addpath(genpath('.//utils'));

%% PARAMETERS
% filename_spc: the .spc file
if ~exist('filename_spc', 'var')
    filename_spc = './/ExampleData//highNA_zoom5.6_avg1slice1_920nmenergy2.5__OG488.spc';
end
% savepath: output directory
if ~exist("savepath", 'var')
    savepath = ['.//output//', datestr(now, 'YYYYmmDD_HHMMSS')];
end
% image size, framerate, and pixel dwell time by ScanImage
if ~exist("cap_sizex", 'var'); cap_sizex = 512; end
if ~exist("cap_sizey", 'var'); cap_sizey = 512; end
if ~exist("cap_frameRate", 'var'); cap_frameRate = 29.97; end
if ~exist("pixelDwellTime", 'var'); pixelDwellTime = 88; end
% bi-directional scanning
if ~exist("flag_biScan", 'var'); flag_biScan = 1; end
if ~exist("lineMarker_dropped", 'var'); lineMarker_dropped = 2; end
% frame average and z scanning
if ~exist("avgFrameNum", 'var'); avgFrameNum = 1; end
if ~exist("znum", 'var'); znum = 1; end
% SPCM settings
if ~exist("unit_macroT", 'var'); unit_macroT = 2.048131; end
if ~exist("unit_microT", 'var'); unit_microT = 4; end
% The actual image size may differ from the displayed image as we are using
% a resonant scanning system
real_sizey = cap_sizey;
real_sizex = round(1e9 / cap_frameRate / real_sizey / pixelDwellTime);
if mod(real_sizex, 2) == 1
    real_sizex = real_sizex + 1; % Ensure even number for bidirectional scanning
end

%% LOAD DATA
disp(['Loading ', filename_spc]);
fid = fopen(filename_spc, 'r');
alldata_8bit = fread(fid, '*uint8');
fclose(fid);

% Convert 8-bit data to 32-bit words
alldata_32bit = typecast(alldata_8bit, 'uint32');
evenetNum = length(alldata_32bit);

%% MICROTIMING CALIBRATION (OFFSET CORRECTION)
% Collect first 10000 photons to determine timing offset
event_count = 0;
photon_count = 1;
numPhotons_forOffset = 10000;
microtime_forOffset = zeros(numPhotons_forOffset, 1);

while event_count < evenetNum
    event_count = event_count + 1;
    data = alldata_32bit(event_count);
    data_binstr = dec2bin(data, 32);

    % Check for photon event (starts with '00')
    if startsWith(data_binstr, '00')
        % Extract microtime (bits 5-16, 12 bits)
        microT = bin2dec(data_binstr(5:16));
        microtime = microT * unit_microT;
        microtime_forOffset(photon_count) = microtime;
        photon_count = photon_count + 1;
    end

    % Stop after collecting enough photons
    if photon_count >= numPhotons_forOffset
        break;
    end
end

% The histogram
figure(1); clf; histogram(microtime_forOffset,1000);

% ===========================================
% ===========================================
% Mannual determination based on the histogram
offset_ps = 650;           % Timing offset in picoseconds
maxDetect_ps = 12500;      % Maximum detectable time range (12.5 ns)
afterPulse_thr_ps = inf;   % After-pulse rejection threshold
% ===========================================
% ===========================================

% Apply offset correction and after pluse removal
microtime_forOffset_beforeCorrection = microtime_forOffset;
microtime_forOffset(microtime_forOffset>maxDetect_ps) = 0;
microtime_forOffset = microtime_forOffset - offset_ps;
microtime_forOffset(microtime_forOffset<0) = ...
    microtime_forOffset(microtime_forOffset<0) + maxDetect_ps;
microtime_forOffset(microtime_forOffset>afterPulse_thr_ps) = 0;
microtime_forOffset(microtime_forOffset==0) = [];

% The histogram
figure(1); clf;
subplot(1,2,1); histogram(microtime_forOffset_beforeCorrection,1000);
title('Before correction');
subplot(1,2,2); histogram(microtime_forOffset,1000);
title('After correction');
drawnow;
close all;

%% LINE CLOCK INTERVAL ANALYSIS
% Scan through events to find line markers and calculate intervals
event_count = 0;
lineMarker_count = 0;
macroOverflow_count = 0;
lineMarker_macroT_list = [];
lineMarker_linesPerClock = 1;

while event_count < evenetNum
    event_count = event_count + 1;
    data = alldata_32bit(event_count);
    data_binstr = dec2bin(data, 32);

    % Check for macrotime overflow event (10000000)
    if startsWith(data_binstr, '10000000')
        macroOverflow_count = macroOverflow_count + 1;
    end

    % Check for line marker (starts with '01')
    if startsWith(data_binstr, '01')
        lineMarker_count = lineMarker_count + 1;
        % Extract macrotime from bits 20-32
        macroT = bin2dec(data_binstr(20:32));
        macroT = (macroOverflow_count * 4096 + macroT);
        
        disp(['FirstLineMarker:', data_binstr, '  Macrotime:', num2str(macroT)]);
        lineMarker_macroT_list(end + 1) = macroT;
        
        % Stop after collecting enough line markers for one frame
        if lineMarker_count == (real_sizey / lineMarker_linesPerClock + 1)
            break;
        end
    end
end

% Calculate line marker intervals
lineMarker_macroT_diff_list = diff(lineMarker_macroT_list);
lineMarkerInterval_macroT_bigIntervals = max(lineMarker_macroT_diff_list);
lineMarker_macroT_diff_list(lineMarker_macroT_diff_list==...
    max(lineMarker_macroT_diff_list)) = [];
lineMarkerInterval_macroT_smallIntervals = mean(lineMarker_macroT_diff_list);

%% FIRST PASS: THE FRAME CLOCK
%%% We decide the frame clock by mannually adjusting the scan phase (sph)

macroOverflow_count = 0;
frameNum_forsph = 300; % we use the first 300 frames
disp(['sph adjust: reconstructing a video of ', num2str(real_sizex), ...
    ' * ', num2str(real_sizey), ' * ', num2str(frameNum_forsph)]);

% Find first line marker and skip dropped markers
event_count = 0;
lineMarker_count = 0;
lineMarker_macroT = 0;

while event_count < evenetNum
    event_count = event_count + 1;
    data = alldata_32bit(event_count);
    data_binstr = dec2bin(data, 32);

    % Check for macrotime overflow
    if startsWith(data_binstr, '10000000')
        macroOverflow_count = macroOverflow_count + 1;
    end

    % Check for line marker
    if startsWith(data_binstr, '01')
        lineMarker_count = lineMarker_count + 1;
        macroT = bin2dec(data_binstr(20:32));
        macroT = (macroOverflow_count * 4096 + macroT);
        disp(['FirstLineMarker:', data_binstr, '  Macrotime:', num2str(macroT)]);
        lineMarker_macroT = macroT;
        
        if lineMarker_count == lineMarker_dropped
            lineMarker_count = 1;
            break;
        end
    end
end

event_count_start = event_count;
macroOverflow_count_start = macroOverflow_count;
lineMarker_macroT_startForsph = lineMarker_macroT;

% Reconstruct first frameNum_forsph frames for SPH adjustment
stack_photonNum_forsph = zeros(real_sizex, real_sizey * frameNum_forsph, 'uint16');

while event_count < evenetNum
    event_count = event_count + 1;
    data = alldata_32bit(event_count);
    data_binstr = dec2bin(data, 32);

    % Check for macrotime overflow
    if startsWith(data_binstr, '10000000')
        macroOverflow_count = macroOverflow_count + 1;
        continue;
    end

    % Check for line marker
    if startsWith(data_binstr, '01')
        lineMarker_count = lineMarker_count + 1;
        macroT = bin2dec(data_binstr(20:32));
        macroT = (macroOverflow_count * 4096 + macroT);
        lineMarker_macroT = macroT;
        continue;
    end

    % Check for photon event
    if startsWith(data_binstr, '00')
        % Extract microtime and macrotime
        microT = bin2dec(data_binstr(5:16));
        macroT = bin2dec(data_binstr(20:32));
        macroT = macroOverflow_count * 4096 + macroT;
        microtime = microT * unit_microT;

        % Calculate pixel position
        x = ceilOrAdd1((macroT - lineMarker_macroT) * unit_macroT / pixelDwellTime);
        if x > real_sizex
            continue;
        end
        x = modOrDivisor(x, real_sizex);
        y = lineMarker_count + floor(x / real_sizex);

        if y >= real_sizey * frameNum_forsph
            break;
        end

        stack_photonNum_forsph(x, y) = stack_photonNum_forsph(x, y) + 1;
    end

    % Progress display
    if mod(y, real_sizey * 10) == 0
        disp(['x=',num2str(x),' y=',num2str(modOrDivisor(y,real_sizey)), ...
            ' frame=', num2str(ceil(y/real_sizey)), ...
            ' microT=', num2str(microT), ...
            ' microtime=', num2str(microtime)]);
    end

    if y >= real_sizey * frameNum_forsph
        break;
    end
end

% Reshape and sum frames
stack_photonNum_forsph = reshape(stack_photonNum_forsph, ...
    [real_sizex, real_sizey, frameNum_forsph]);
stack_photonNum_forsph_sum = sum(stack_photonNum_forsph, 3);

% To find the optimal sph and get the start of the frame
sph_start = 100 - 2*real_sizex*300;
sph_step = 2*real_sizex;
sph_end = 100 - 2*real_sizex*1;
sph_array  = sph_start : sph_step : sph_end;

sphAdjStackName = [savepath, '//stack_photonNum_forsph_sum_sphAdjust_',...
    num2str(sph_start), '-', num2str(sph_step), '-', num2str(sph_end),...
    'pixels.tif'];
disp(sphAdjStackName);
opt.append = true;
for sph = sph_array
    disp(num2str(sph));
    stack_photonNum_forsph_sum_sph = circshift(stack_photonNum_forsph_sum(:), sph);
    stack_photonNum_forsph_sum_sph = reshape(stack_photonNum_forsph_sum_sph, ...
        [real_sizex, real_sizey]);
    
    if flag_biScan
        for y = 1 : real_sizey
            if mod(y, 2) == 0
                stack_photonNum_forsph_sum_sph(:, y) = ...
                    flip(stack_photonNum_forsph_sum_sph(:, y));
            end
        end
    end
    saveastiff(permute(single(stack_photonNum_forsph_sum_sph), [2,1,3]), ...
        sphAdjStackName, opt);
end
%%% If the image flips left and right, modify the value of 'lineMarker_dropped'

% ===========================================
% ===========================================
% after checking the output intensity image
sph = sph_array(233); % the start of a frame
% ===========================================
% ===========================================

% Apply frame correction by removing misaligned pixels
stack_pharsp = stack_photonNum_forsph(:);
stack_photonNum_forsph = stack_photonNum_forsph(-sph+1:end);
stack_photonNum_forsph = stack_photonNum_forsph(1:real_sizex*real_sizey*(frameNum_forsph-1));
stack_photonNum_forsph = reshape(stack_photonNum_forsph, ...
    [real_sizex, real_sizey, frameNum_forsph-1]);

% Apply bidirectional scanning correction
if flag_biScan
    for frame = 1 : size(stack_photonNum_forsph, 3)
        for y = 1 : real_sizey
            if mod(y, 2) == 0
                stack_photonNum_forsph(:, y, frame) = ...
                    flip(stack_photonNum_forsph(:, y, frame));
            end
        end
    end
end

% Save intermediate result and drop the start frames
saveastiff_overwrite(permute(single(stack_photonNum_forsph),[2,1,3]),...
    [savepath, '//stack_photonNum_forsph_nosum.tif']);

% ===========================================
% ===========================================
% Some times we drop the first several frames
framesDropped = 0;
% ===========================================
% ===========================================

% Save calibrations
save([savepath, '//scanPhase.mat'], 'sph', 'framesDropped', 'lineMarker_dropped');

% To get the macroT of the first frame clock: macroT_start
sph_line_div = floor((-sph) ./ (real_sizex*lineMarker_linesPerClock));
sph_line_rem = rem(-sph, (real_sizex*lineMarker_linesPerClock));
macroT_start = lineMarker_macroT_startForsph + ...
    sph_line_div * lineMarkerInterval_macroT_smallIntervals + ...
    sph_line_rem * pixelDwellTime / unit_macroT;

% Sometimes there is a need of a big interval between line clocks
flag_lineMarkerInterval_macroT_needbigIntervals = 0;
if flag_lineMarkerInterval_macroT_needbigIntervals
    macroT_start = macroT_start - lineMarkerInterval_macroT_smallIntervals + ...
        lineMarkerInterval_macroT_bigIntervals;
end

%% SECOND PASS: PRECISE DETERMINATION OF THE SCAN PHASE
%%% To remove the residual scan phase and also to double check macroT_start

% Skip photons before macroT_start
event_count = 0;
macroOverflow_count = 0;
lineMarker_count = 0;
lineMarker_macroT = 0;
macroT = 0;

while event_count < evenetNum
    event_count = event_count + 1;
    data = alldata_32bit(event_count);
    data_binstr = dec2bin(data, 32);

    % Check for macrotime overflow
    if startsWith(data_binstr, '10000000')
        macroOverflow_count = macroOverflow_count + 1;
        continue;
    end

    % Check for line marker
    if startsWith(data_binstr, '01')
        lineMarker_count = lineMarker_count + 1;
        macroT = bin2dec(data_binstr(20:32));
        macroT = (macroOverflow_count * 4096 + macroT);
        lineMarker_macroT = macroT;
        continue;
    end

    % Check for photon event
    if startsWith(data_binstr, '00')
        microT = bin2dec(data_binstr(5:16));
        macroT = bin2dec(data_binstr(20:32));
        macroT = macroOverflow_count * 4096 + macroT;
    end

    % Stop when reaching macroT_start
    if macroT >= macroT_start
        break
    else
        if mod(event_count, 1e6) == 0
            disp(['Dropping photons: ', num2str(macroT), ...
                ' ||| ', num2str(macroT_start)]);
        end
    end
end

bias = lineMarker_macroT - macroT_start;
lineMarker_macroT = macroT_start;

% Reconstruct 200 frames
lineMarker_count = 1;
frameNum_forMacroTStart = 200;
stack_photonNum_forMacroTStart = zeros(real_sizex, real_sizey * ...
    frameNum_forMacroTStart, 'uint16');

while event_count < evenetNum
    event_count = event_count + 1;
    data = alldata_32bit(event_count);
    data_binstr = dec2bin(data, 32);

    % Check for macrotime overflow
    if startsWith(data_binstr, '10000000')
        macroOverflow_count = macroOverflow_count + 1;
        continue;
    end

    % Check for line marker
    if startsWith(data_binstr, '01')
        lineMarker_count = lineMarker_count + 1;
        macroT = bin2dec(data_binstr(20:32));
        macroT = macroOverflow_count * 4096 + macroT;
        lineMarker_macroT = macroT;
        lineMarker_macroT = lineMarker_macroT - bias;
        continue;
    end

    % Check for photon event
    if startsWith(data_binstr, '00')
        microT = bin2dec(data_binstr(5:16));
        microtime = microT * unit_microT;
        macroT = bin2dec(data_binstr(20:32));
        macroT = macroOverflow_count * 4096 + macroT;

        % Calculate pixel position
        x = ceilOrAdd1((macroT - lineMarker_macroT) * unit_macroT / pixelDwellTime);
        y = lineMarker_count + floor(modOrDivisor(x, real_sizex) / real_sizex);
        x = modOrDivisor(x, real_sizex);
        
        if (macroT - lineMarker_macroT) < 0
            y = y - 1;
        end

        if y >= real_sizey * frameNum_forMacroTStart
            break;
        end

        stack_photonNum_forMacroTStart(x, y) = ...
            stack_photonNum_forMacroTStart(x, y) + 1;
    end

    % Progress display
    if mod(y, real_sizey) == 0
        disp(['x=',num2str(x),' y=',num2str(modOrDivisor(y,real_sizey)), ...
            ' frame=', num2str(ceil(y/real_sizey)), ...
            ' microT=', num2str(microT), ...
            ' microtime=', num2str(microtime)]);
    end

    if y >= real_sizey * frameNum_forMacroTStart
        break;
    end
end

stack_photonNum_forMacroTStart = reshape(stack_photonNum_forMacroTStart, ...
    [real_sizex, real_sizey, frameNum_forMacroTStart]);
stack_photonNum_forMacroTStart_sum = sum(stack_photonNum_forMacroTStart, 3);

% To find the optimal sph and fine-tune macroT_start
sph_start = -50;
sph_step = 1;
sph_end = 50;
sph_array  = sph_start : sph_step : sph_end;

sphAdjStackName = [savepath, '//stack_photonNum_forMacroTStart_sum_sphAdjust_',...
    num2str(sph_start), '-', num2str(sph_step), '-', num2str(sph_end),...
    'pixels.tif'];
disp(sphAdjStackName);
opt.append = true;

for sph = sph_array
    disp(num2str(sph));
    stack_photonNum_forMacroTStart_sum_sph = circshift(...
        stack_photonNum_forMacroTStart_sum(:), sph);
    stack_photonNum_forMacroTStart_sum_sph = reshape(...
        stack_photonNum_forMacroTStart_sum_sph, [real_sizex, real_sizey]);

    if flag_biScan
        for y = 1 : real_sizey
            if mod(y, 2) == 0
                stack_photonNum_forMacroTStart_sum_sph(:, y) = ...
                    flip(stack_photonNum_forMacroTStart_sum_sph(:, y));
            end
        end
    end
    saveastiff(permute(single(stack_photonNum_forMacroTStart_sum_sph), [2,1,3]), ...
        sphAdjStackName, opt);
end

% ===========================================
% ===========================================
% after checking the output intensity image
sph = sph_array(51); % to remove the residual scan phase
% ===========================================
% ===========================================

% Save calibrations
save([savepath, '//scanPhase_residual.mat'], ...
    'flag_lineMarkerInterval_macroT_needbigIntervals', 'sph');

% Update macroT_start based on residual scan phase
macroT_start = macroT_start + (-sph) * pixelDwellTime / unit_macroT;


%% RECONSTRUCTION OF THE ENTIRE PHOTON-ARRIVAL VIDEO STACK

% Skip photons before updated macroT_start
event_count = 0;
macroOverflow_count = 0;
lineMarker_count = 0;
lineMarker_macroT = 0;
macroT = 0;

while event_count < evenetNum
    event_count = event_count + 1;
    data = alldata_32bit(event_count);
    data_binstr = dec2bin(data, 32);

    % Check for macrotime overflow
    if startsWith(data_binstr, '10000000')
        macroOverflow_count = macroOverflow_count + 1;
        continue;
    end

    % Check for line marker
    if startsWith(data_binstr, '01')
        lineMarker_count = lineMarker_count + 1;
        macroT = bin2dec(data_binstr(20:32));
        macroT = (macroOverflow_count * 4096 + macroT);
        lineMarker_macroT = macroT;
        continue;
    end

    % Check for photon event
    if startsWith(data_binstr, '00')
        microT = bin2dec(data_binstr(5:16));
        macroT = bin2dec(data_binstr(20:32));
        macroT = macroOverflow_count * 4096 + macroT;
    end

    if macroT >= macroT_start
        break
    else
        if mod(event_count, 1e6) == 0
            disp(['Dropping photons: ', num2str(macroT), ...
                ' ||| ', num2str(macroT_start)]);
        end
    end
end

bias = lineMarker_macroT - macroT_start;
lineMarker_macroT = macroT_start;

% Estimate total frames and allocate memory
lineMarker_count = 1;
num_macroT = nnz(alldata_32bit == 2147483648) - 1; % Count overflow events
num_pixels = round(num_macroT * 4096 * unit_macroT / pixelDwellTime);
frameNum = ceil(num_pixels / real_sizex / real_sizey) - framesDropped - 2;
frameNum = ceil(frameNum ./ avgFrameNum);
frameNum_eachz = floor(frameNum / znum);

stack_photonNum = zeros(real_sizex, real_sizey, frameNum, 'single');
stack_lt = zeros(real_sizex, real_sizey, frameNum, 'single');

disp(['Reconstructing a video of size ', num2str(real_sizex), ...
    ' * ', num2str(real_sizey), ' * ',  num2str(frameNum)]);

frameCountBefore = 0;
frameInfoNow = 1;
stack_photonNum_temp = zeros(real_sizex, real_sizey, 'single');
stack_lt_temp = zeros(real_sizex, real_sizey, 'single');

% Photon assignment with arrival time
while event_count < evenetNum
    event_count = event_count + 1;
    data = alldata_32bit(event_count);
    data_binstr = dec2bin(data, 32);

    % Check for macrotime overflow
    if startsWith(data_binstr, '10000000')
        macroOverflow_count = macroOverflow_count + 1;
        continue;
    end

    % Check for line marker
    if startsWith(data_binstr, '01')
        lineMarker_count = lineMarker_count + 1;
        macroT = bin2dec(data_binstr(20:32));
        macroT = macroOverflow_count * 4096 + macroT;
        lineMarker_macroT = macroT;
        lineMarker_macroT = lineMarker_macroT - bias;
        continue;
    end

    % Check for photon event
    if startsWith(data_binstr, '00')
        % Extract microtime and macrotime
        microT = bin2dec(data_binstr(5:16));
        microtime = microT * unit_microT;
        macroT = bin2dec(data_binstr(20:32));
        macroT = macroOverflow_count * 4096 + macroT;

        % Calculate pixel position
        x = ceilOrAdd1((macroT - lineMarker_macroT) * unit_macroT / pixelDwellTime);
        y = lineMarker_count + floor(modOrDivisor(x, real_sizex) / real_sizex);
        x = modOrDivisor(x, real_sizex);
        
        if (macroT - lineMarker_macroT) < 0
            y = y - 1;
        end

        % Progress display
        if mod(y, real_sizey * 100) == 0
            disp(['x=',num2str(x),' y=',num2str(modOrDivisor(y,real_sizey)), ...
                ' frame=', num2str(ceil(y/real_sizey)), ...
                ' microT=', num2str(microT), ...
                ' microtime=', num2str(microtime)]);
        end

        % Skip invalid frames
        if y <= 0; continue; end

        frame = ceil(y/real_sizey)-framesDropped;
        y = modOrDivisor(y,real_sizey);

        % Reset temporary buffers at frame boundary
        if frame == 0
            stack_photonNum_temp = zeros(real_sizex, real_sizey, 'single');
            stack_lt_temp = zeros(real_sizex, real_sizey, 'single');
        end

        % Save averaged frame when enough frames are collected
        if (frame > 0) && ((frame - frameCountBefore) > avgFrameNum)
            stack_lt_temp_save = stack_lt_temp;

            % Apply bidirectional scanning correction
            if flag_biScan
                for ff = 1 : size(stack_lt_temp_save, 3)
                    for yy = 1 : real_sizey
                        if mod(yy, 2) == 0
                            stack_lt_temp_save(:, yy, ff) = ...
                                flip(stack_lt_temp_save(:, yy, ff));
                        end
                    end
                end
            end

            % Apply timing offset correction
            stack_lt_temp_save(stack_lt_temp_save>maxDetect_ps) = 0;
            stack_lt_temp_save_nzInd = stack_lt_temp_save > 1e-3;
            stack_lt_temp_save(stack_lt_temp_save_nzInd) = ...
                stack_lt_temp_save(stack_lt_temp_save_nzInd) - offset_ps;
            stack_lt_temp_save(stack_lt_temp_save<0) = ...
                stack_lt_temp_save(stack_lt_temp_save<0) + maxDetect_ps;
            stack_lt_temp_save(stack_lt_temp_save>afterPulse_thr_ps) = 0;

            % Calculate average lifetime and photon count
            stack_lt(:, :, frameInfoNow) = mean_nz(stack_lt_temp_save, 3);
            stack_photonNum(:, :, frameInfoNow) = ...
                sum(stack_lt_temp_save > 1e-3, 3);

            % Crop and save individual frame
            cropPart = ((real_sizex - cap_sizex) / 2 + 1) : ...
                       ((real_sizex - cap_sizex) / 2 + cap_sizex);
            stack_lt_temp_save = stack_lt_temp_save(cropPart,:,:);
            opt.overwrite = true;
            opt.message = false;

            frameInfoNow_whichZ = modOrDivisor(frameInfoNow, znum);
            frameInfoNow_inThisZ = ceil(frameInfoNow / znum);

            saveastiff(permute(single(stack_lt_temp_save),[2,1,3]),...
                [savepath, '//groupmean', num2str(avgFrameNum), '_z', ...
                num2str(frameInfoNow_whichZ),'//stack_ltframes_crop//frame_', ...
                num2str(frameInfoNow_inThisZ, '%06d'), '.tif'], opt);

            % Update frame counter
            while (frame - frameCountBefore) > avgFrameNum
                frameCountBefore = frameCountBefore + avgFrameNum;
            end
            stack_photonNum_temp = zeros(real_sizex, real_sizey, 'single');
            stack_lt_temp = zeros(real_sizex, real_sizey, 'single');
            frameInfoNow = frameInfoNow + 1;
        end

        % Accumulate photon data
        stack_photonNum_temp(x, y) = stack_photonNum_temp(x, y) + 1;
        thisPixel = stack_lt_temp(x,y,:);
        thisPixel_numnz = sum(thisPixel ~= 0);
        stack_lt_temp(x,y,thisPixel_numnz+1) = microtime;
    end
end

%% SAVE SUMMARY IMAGES
stack_photonNum_sum = sum(stack_photonNum, 3);

% Crop
cropPart = ((real_sizex - cap_sizex) / 2 + 1) : ...
           ((real_sizex - cap_sizex) / 2 + cap_sizex);

stack_photonNum_crop = stack_photonNum(cropPart,:,:);
stack_lt_crop = stack_lt(cropPart,:,:);
stack_photonNum_crop_sum = sum(stack_photonNum_crop, 3);

% Save photon counts by z-plane
for z = 1:znum
    saveastiff_overwrite(permute(single(stack_photonNum_crop(:,:,z:znum:end)),[2,1,3]),...
        [savepath, '//groupmean', num2str(avgFrameNum), '_z', num2str(z), ...
        '//stack_photonNum_crop.tif']);
end

% Save fastFLIM (center of mass method, CMM) by z-plane
for z = 1:znum
    saveastiff_overwrite(permute(single(stack_lt_crop(:,:,z:znum:end)),[2,1,3]),...
        [savepath, '//groupmean', num2str(avgFrameNum), '_z', num2str(z), ...
        '//stack_lt_crop.tif']);
end
