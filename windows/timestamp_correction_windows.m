% Timestamp synchronization of high framerate video with an EEG recording
% system
%
% Nico Alavi, 31. Dec 2018, <nico.alavi aT fu-berlin.de>
% Leibniz-Institute for Neurobiology, Magdeburg
% Department Functional Architecture of Memory
%
% For further information see 'README.md'.

clear
filepath = input('Enter path to files: ');

%% Open and read digialIO (from Axona) files
digitalIO_file = get_file(filepath, '*_digitalIO.txt');
[out_path, out_name, out_ext] = fileparts(digitalIO_file); % for file output later
comma2point_overwrite(digitalIO_file); % replace commas with dots
[dtime, dtype, dvalue] = textread(digitalIO_file, '%f %s %u', 'headerlines', 1, 'endofline', '\r\n'); % read data from file, skip 5 first lines since video recording starts after that

% value explanation:
% 4 -> frame captured
% 2 -> button pressed
% 6 (4+2) -> frame captured and button pressed at the same time
% 0 -> event stopped

% remove the event stopped (value == 0) entries since we only need to
% consider beginning of event (e.g. start recording frame)
dtype = dtype(dvalue == 'INPUT');
dtime = dtime(dvalue ~= 0);
dvalue = dvalue(dvalue ~= 0);

% get timestamps of when the button was pressed
button = get_button(dtime, dvalue);
num_button = length(button);

% Get timestamps of each frame the way the axona device detected them by
% receiving a TTL pulse directly from the camera every time a frame was
% captured
axona = dtime(dvalue >= 4);
axona_start = axona(1); % time in s when recording started after device was turned on, used to subtract from every value to start from 0
axona = sort(axona);

% get corresponding frame index numbers to button press timestamps
% button = button';
[~,button_idx] = intersect(axona, button);

% normalize data, making sure it starts with time 0 and increasing in seconds
axona = axona - axona_start; 
button = button - axona_start; % bringin button timestamps to same format as axona frame timestamps

if ~isempty(button)
    disp('Successfully read axona and button timestamps from .txt file!')
end

%% Open and read CVB timestamp file
cvb_file = get_file(filepath, '*_CVB_TS.txt');
cvb_fid = fopen(cvb_file);
cvb_raw = textscan(cvb_fid, '%s', 'Delimiter', '\n'); % cell containing unformatted CVB timestamps
cvb = get_cvb(cvb_raw); % vector with cvb timestamps in same format as axona timestamps
if ~isempty(cvb)
    disp('Successfully read cvb timestamps from .txt file!')
end

%% Open and read LED timestamp file
led_file = get_file(filepath, '*_LED.txt');
[line_num, led_idx, led_ts] = textread(led_file, '%d %d %f', 'headerlines', 1, 'endofline', '\r\n'); 
if ~isempty(led_ts)
    disp('Successfully read LED timestamps from .txt file!')
end

%% Alignment
cvb_corrected_idx = zeros(length(cvb),1); % container to store indices of axona frames corresponding to each cvb frame

% add first and last frame as anchor points to existing button/led pairs to
% align the whole video and not just the intervall between the button/led
% pairs
axona_anchor = [1; button_idx; length(axona)];
cvb_anchor = [1; led_idx; length(cvb)];

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

% Use the frame index alignment vector to assign new timestamps to the cvb timestamps
cvb_corrected_ts = axona(cvb_corrected_idx);

%% Save results to .txt files
out_name = out_name(1:17);
corrected_idx_with_ts = [cvb_corrected_idx'; cvb_corrected_ts'];
fileID = fopen(strcat(filepath, '\', out_name,'_corrected_TS.txt'),'w');
fprintf(fileID, '%8s %10s\r\n','Index', 'Timestamp');
fprintf(fileID,'%8d %10.3f\r\n',corrected_idx_with_ts);
fclose(fileID);

%% Summary file
fileID = fopen(strcat(filepath, '/', out_name,'_statistic.txt'),'w');
fprintf(fileID, 'Statistic of the timestamp correction for %s.\r\n\r\n', out_name);

fprintf(fileID, 'Total frames acquired by the camera: %d\r\n', length(axona));
fprintf(fileID, 'Total frames recorded by CVB: %d\r\n', length(cvb));
fprintf(fileID, 'Number of frames CVB dropped: %d\r\n', length(axona)-length(cvb));
fprintf(fileID, 'Mean time difference between Axona and CVB anchor points: %.3fs\r\n\r\n', mean(led_ts-button'));

fprintf(fileID, 'Difference in number of frames between two successive anchor points\r\n\r\n');
fprintf(fileID, '%8s %8s %10s\r\n', 'Axona', 'CVB', 'Axona-CVB');
anchor_diff = [diff(axona_anchor)'; diff(cvb_anchor)'; inter_anchor_diff'];
fprintf(fileID, '%8d %8d %10d\r\n', anchor_diff);

fclose(fileID);

%% Plots
f = figure;
subplot(2,1,1);
plot(1:length(axona),axona);
hold on;
plot(1:length(cvb),cvb);
plot(button_idx, button, 'kx');
title('Axona vs CVB');
xlabel('frame number');
ylabel('time [s]');
legend({'Axona', 'CVB', 'Button presses'}, 'Location', 'north');
hold off;

subplot(2,1,2);
plot(1:length(axona),axona);
hold on;
plot(cvb_corrected_idx, cvb_corrected_ts);
plot(button_idx, button, 'kx');
title('Axona vs CVB (corrected)');
xlabel('frame number');
ylabel('time [s]');
legend({'Axona', 'CVB (corrected)', 'Button presses'}, 'Location', 'north');
hold off;

savefig(f, strcat(filepath, '\', out_name,'_TimePerFrame.fig'));
disp('Timestamp correction complete!')