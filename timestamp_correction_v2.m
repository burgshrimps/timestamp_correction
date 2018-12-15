clear;

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

% for i = 1:length(inter_anchor_diff)
%     disp(i)
%     % if there is no difference in frame numbers assign frames linearly
%     % without further analysis necessary
%     if inter_anchor_diff(i) == 0
%        cvb_corrected_idx(cvb_anchor(i)+1:cvb_anchor(i+1)-1) = axona_anchor(i)+1:axona_anchor(i+1)-1; 
%     elseif inter_anchor_diff(i) > 0 % if difference > 0 more frames between button anchor point, meaning cvb skipped frames
%         % choose random index n times with n being inter_anchor_diff(i) in
%         % current anchor window. use this random index/indices to determine
%         % which axona frame should be skipped during the alignment (meaning
%         % which cvb frame was skipped during recording)
%         rndm_idx = randi([axona_anchor(i)+1 axona_anchor(i+1)-1],inter_anchor_diff(i),1); 
%         tmp_idx = axona_anchor(i)+1 : axona_anchor(i+1)-1; 
%         tmp_idx(rndm_idx) = []; % delete (skip) n random frames at previously determinded positions
%         cvb_corrected_idx(cvb_anchor(i)+1:cvb_anchor(i+1)-1) = tmp_idx;
%     else
%         rndm_idx = randi([cvb_anchor(i)+1 cvb_anchor(i+1)-1],abs(inter_anchor_diff(i)),1);
%         disp(rndm_idx)
%         tmp_idx = cvb_anchor(i)+1 : cvb_anchor(i+1)-1; 
%         tmp_idx(rndm_idx) = []; % delete (skip) n random frames at previously determinded positions
%         cvb_corrected_idx(tmp_idx) = axona_anchor(i)+1:axona_anchor(i+1)-1;
%     end
% end

%% Function
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

%% Notes
% - regression not necessary, slopes of axona and cvb same
















