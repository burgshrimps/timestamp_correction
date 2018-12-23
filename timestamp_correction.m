% Script to correct video timestamps recorded with a highspeed camera
%
% Nico Alavi, 22. Dec 2018, <nico.alavi aT fu-berlin.de>
% Leibniz-Institute for Neurobiology, Magdeburg
% Department Functional Architecture of Memory
%
% For further information see 'README.md'.

clear
format long

%% Input
filepath = input('Enter path to files: ');

%% Open and read digialIO files
digitalIO_info = strcat(filepath,'/','*_digitalIO.txt'); % get frame timestamp.txt file in current directory
digitalIO_struct = dir(digitalIO_info);
digitalIO_name = digitalIO_struct.name;
digitalIO_file = strcat(filepath, '/', digitalIO_name);
comma2point_overwrite(digitalIO_file); % replace commas with dots to read in correctly
[dtime, dtype, dvalue] = textread(digitalIO_file, '%f %s %u', 'headerlines', 5, 'endofline', '\r\n'); % read data from file, skip 5 first lines since video recording starts after that

% value explanation:
% 4 -> frame captured
% 2 -> button pressed
% 6 (4+2) -> frame captured and button pressed at the same time
% 0 -> event stopped

% remove the event stopped (value == 0) entries since we only need to
% consider beginning of event (e.g. start recording frame)
dtype = dtype(dvalue ~= 0);
dtime = dtime(dvalue ~= 0);
dvalue = dvalue(dvalue ~= 0);

% Get timestamps of each frame the way the axona device detected them by
% receiving a TTL pulse directly from the camera every time a frame was
% captured
axona = dtime(dvalue >= 4);
axona_start = axona(1); % time in s when recording started after device was turned on, used to subtract from every value to start from 0

% Get button press timestamps from the digitalIO file
button_all = dtime(dvalue == 6);

% Filter button timestamps since we only need the first frame in which it was
% pressed every time and digitalIO contains every frame the button remained
% pressed
button = filterbutton(button_all);
button = button'; %transpose vector so it has same format as led vector
[~,button_frm_idx] = intersect(axona, button); % corresponding frame index numbers to button press timestamps

% normalize data, making sure it starts with time 0 and increasing in seconds
axona = axona - axona_start; 
axona = sort(axona);
button = button - axona_start; % bringin button timestamps to same format as axona frame timestamps

%% Open and read CVB timestamp files 
% (presentation timestamp), which contain the timestamps of the actual
% finished video. These timestamps are the flawed ones since sometimes
% frames are skipped and therefore inaccurate
cvb_info = strcat(filepath, '/', '*_CVB_TS.txt'); % get cvb timestamp .txt file in current directory
cvb_struct = dir(cvb_info);
cvb_name = cvb_struct.name;
cvb_file = strcat(filepath, '/', cvb_name);
cvb_fid = fopen(cvb_file);
cvb_raw = textscan(cvb_fid, '%s', 'Delimiter', '\n');

% Insert missing zeros
cvb_raw = cvb_raw{1}(:); % cell formatting
zeros_idx = find(cellfun(@(x) length(x), cvb_raw) < 23); % find those lines which dont exceed a certain length (23). Those are the lines which are missing a zero on the tens decimal position
cvb_raw(zeros_idx) = cellfun(@(x) insert_zeros(x), cvb_raw(zeros_idx)); % correct the lines in question

% Convert datetime timestamp to timestamp format of axona (starting with zero increasing in seconds)
formatIn = 'yy/mm/dd HH:MM:SS.FFF';
start_ts = datevec(cvb_raw{1}, formatIn);
cvb = etime(datevec(cvb_raw(:), formatIn), start_ts);
cvb = sort(cvb);

%% Open and read LED timestamps 
led_ts_info = strcat(filepath, '/', '*_videoTS.txt'); % get led timestamp .txt file in current directory
led_ts_struct = dir(led_ts_info);
led_ts_name = led_ts_struct.name;
led_ts_file = strcat(filepath, '/', led_ts_name);

led_ts_fid = fopen(led_ts_file);
led_cell = textscan(led_ts_fid, '%f', 'Delimiter', ',');
led = led_cell{1};

% Open and read LED frame number 
led_idx_info = strcat(filepath, '/', '*_videoIDX.txt'); % get led timestamp .txt file in current directory
led_idx_struct = dir(led_idx_info);
led_idx_name = led_idx_struct.name;
led_idx_file = strcat(filepath, '/', led_idx_name);

led_idx_fid = fopen(led_idx_file);
led_idx_cell = textscan(led_idx_fid, '%f', 'Delimiter', ',');
led_frm_idx = led_idx_cell{1};

%% Alignment
cvb_corrected_idx = zeros(length(cvb),1); % container to store indices of axona frames corresponding to each cvb frame

% add first and last frame as anchor points to existing button/led pairs to
% align the whole video and not just the intervall between the button/led
% pairs
axona_anchor = [1; button_frm_idx; length(axona)];
cvb_anchor = [1; led_frm_idx; length(cvb)];

% assign the cvb anchor frames to corresponding axona anchor frames
cvb_corrected_idx(cvb_anchor) = axona_anchor;

% compares number of frames that are between two anchor points for cvb and
% axona
% e.g. how many frames between axona_anchor(1) and (2) - how many frames
% between cvb_anchor(1) and (2)
inter_anchor_diff = diff(axona_anchor) - diff(cvb_anchor);

for i = 1:length(inter_anchor_diff)
    % if there is no difference in frame numbers assign frames linearly
    % without further analysis necessary
    if inter_anchor_diff(i) == 0
       cvb_corrected_idx(cvb_anchor(i)+1:cvb_anchor(i+1)-1) = axona_anchor(i)+1:axona_anchor(i+1)-1; 
    elseif inter_anchor_diff(i) > 0 % if difference > 0 more frames between button anchor point, meaning cvb skipped frames
        % evenly distribute indices to be deleted to minimize error by
        % shifting frames, use this index/indices to determine
        % which axona frame should be skipped during the alignment (meaning
        % which cvb frame was skipped during recording)
        tmp_idx = axona_anchor(i)+1:axona_anchor(i+1)-1; % all frame indices between current axona anchor point and the next one
        len = length(tmp_idx);
        del_idx = evenly_distr_idx(len, inter_anchor_diff(i)); % choose frames which should be skipped evenly distributed over the given interval
        tmp_idx(del_idx) = [];
        cvb_corrected_idx(cvb_anchor(i)+1:cvb_anchor(i+1)-1) = tmp_idx;
        
    else
        % if difference < 0: more frames between cvb anchor point
        % could be result of LED detection delay or due to electrical
        % issues in the button box
        tmp_idx = cvb_anchor(i)+1:cvb_anchor(i+1)-1; % all frame indices between current cvb anchor point and the next one
        len = length(tmp_idx);
        del_idx = evenly_distr_idx(len, abs(inter_anchor_diff(i)));  % choose frames which should be skipped evenly distributed over the given interval
        tmp_idx(del_idx) = [];
        cvb_corrected_idx(tmp_idx) = axona_anchor(i)+1:axona_anchor(i+1)-1;
    end
end

% because of the case where the difference is < 0 some entries in
% cvb_corrected_idx don't have a corresponding axona index assigned to them
% for these entries I assign them to the axona frame which was assigned to
% the cvb frame before said entry
cvb_idx_to_fill = find(cvb_corrected_idx == 0);
cvb_corrected_idx(cvb_idx_to_fill) = cvb_corrected_idx(cvb_idx_to_fill-1);

%% Use the frame index alignment vector to assign new timestamps to the cvb timestamps
cvb_corrected_ts = axona(cvb_corrected_idx);

%% Save results to .txt files
corrected_idx_with_ts = [cvb_corrected_idx'; cvb_corrected_ts'];
fileID = fopen(strcat(cvb_name(1:14),'corrected_TS.txt'),'w');
fprintf(fileID, '%8s %10s\n','Index', 'Timestamp');
fprintf(fileID,'%8d %10.3f\n',corrected_idx_with_ts);
fclose(fileID);

%% Summary file
fileID = fopen(strcat(cvb_name(1:14),'statistic.txt'),'w');
fprintf(fileID, 'Statistic of the timestamp correction for %s.\n\n', cvb_name(1:13));

fprintf(fileID, 'Total frames acquired by the camera: %d\n', length(axona));
fprintf(fileID, 'Total frames recorded by CVB: %d\n', length(cvb));
fprintf(fileID, 'Number of frames CVB dropped: %d\n', length(axona)-length(cvb));
fprintf(fileID, 'Mean time difference between Axona and CVB anchor points: %.3fs\n\n', mean(led-button));

fprintf(fileID, 'Difference in number of frames between two successive anchor points\n\n');
fprintf(fileID, '%8s %8s %10s\n', 'Axona', 'CVB', 'Axona-CVB');
anchor_diff = [diff(axona_anchor)'; diff(cvb_anchor)'; inter_anchor_diff'];
fprintf(fileID, '%8d %8d %10d\n', anchor_diff);

fclose(fileID);

%% Plots
f = figure;
subplot(2,1,1);
plot(1:length(axona),axona);
hold on;
plot(1:length(cvb),cvb);
plot(button_frm_idx, button, 'kx');
title('Axona vs CVB');
xlabel('frame number');
ylabel('time [s]');
legend({'Axona', 'CVB', 'Button presses'}, 'Location', 'north');
hold off;

subplot(2,1,2);
plot(1:length(axona),axona);
hold on;
plot(cvb_corrected_idx, cvb_corrected_ts);
plot(button_frm_idx, button, 'kx');
title('Axona vs CVB (corrected)');
xlabel('frame number');
ylabel('time [s]');
legend({'Axona', 'CVB (corrected)', 'Button presses'}, 'Location', 'north');
hold off;

savefig(f, strcat(cvb_name(1:14),'TimePerFrame.fig'));

%% Functions
function comma2point_overwrite(filespec)
    % Replaces all commas in a .txt file with dots
    file    = memmapfile(filespec, 'writable', true);
    comma   = uint8(',');
    point   = uint8('.');
    file.Data(transpose(file.Data==comma)) = point;
end 

function button = filterbutton(button_all)
    % filters list of button presses to only use the timestamp in which the
    % button was pressed first (there gotta be a 2s difference between the
    % button presses in order to be considered unique)
    button = zeros(1,30);
    button(1) = button_all(1);
    j = 2;
    for k = 2:length(button_all) 
        if abs(button(j-1) - button_all(k)) > 2
            button(j) = button_all(k);
            j = j + 1;
        end
    end
end

function new_str = insert_zeros(str)
    % inserts zeros in timestamp string depending on how long the string is
    str = char(str);
    new_str = strcat(str(1:20),'0',str(21:end));
    new_str = {new_str};
end

function result_idx = evenly_distr_idx(len, num_miss_frames)
    % gets length of an interval and number of missed frames and returns
    % evenly distributed index positions 
    result_idx = zeros(1,num_miss_frames);
    tmp = len/(num_miss_frames+1);
    for i = 1:num_miss_frames
        result_idx(i) = round(i * tmp);
    end
end