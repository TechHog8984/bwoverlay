module main

import os
import strings
import regex
import net.http
import json

struct State {
mut:
	is_running bool
	username_queue []string
	text[] string
}

fn main() {
	mut apikey_file := os.open("apikey.txt") or {
		eprintln("Failed to open apikey.txt. Err: ${err}")
		return
	}
	mut apikey_bytes := []u8{ len: 1 }
	mut apikey_builder := strings.new_builder(40)
	for {
		apikey_file.read(mut apikey_bytes) or {
			if apikey_file.eof() {
				break
			} else {
				eprintln("Failed to read apikey.txt. Err: ${err}")
				return
			}
		}

		apikey_builder.write_u8(apikey_bytes[0])
	}

	apikey := apikey_builder.str()

	apikey_builder.clear()
	apikey_file.close()

	mut state := State{true, []string{}, []string{}}

	cli_thread := spawn cli(mut &state)
	logfile_thread := spawn logfile(mut &state, apikey)

	cli_thread.wait()
	logfile_thread.wait()
}

fn print_data(username string, apikey string) {
	uuid := get_uuid_from_username(username) or {
		eprintln("Failed to get uuid. Error: ${err}")
		return
	}
	data := get_hypixel_data(uuid, apikey) or {
		eprintln("Failed to get hypixel player data. Error: ${err}")
		return
	}

	level := data.player.achievements.bedwars_level
	finals := data.player.stats.bedwars.final_kills_bedwars
	final_deaths := data.player.stats.bedwars.final_deaths_bedwars
	fkdr := "${finals / final_deaths:.2}"

	println("${username} [${level}*] fkdr: ${fkdr}")
}

fn logfile(mut state &State, apikey string) {
	directory_path := "C:${os.getenv("homepath")}\\.lunarclient\\logs\\game\\"
	files := os.ls(directory_path) or {
		eprintln("Failed to list lunar client game logs directory. Err: ${err}")
		return
	}
	mut log_path := "";
	mut highest_last_modified := i64(0);
	for file in files {
		path := directory_path + file
		last_modified := os.file_last_mod_unix(path)
		if highest_last_modified == 0 || last_modified > highest_last_modified {
			highest_last_modified = last_modified
			log_path = path
		}
	}

	mut file := os.open(log_path) or {
		eprintln("Failed to open log file. Err: ${err}")
		return
	}
	mut pos := u64(0)
	for state.is_running {
		mut bytes := file.read_bytes(1)
		mut builder := strings.new_builder(100)
		mut lines := []string{}
		for {
			file.read_from(pos, mut bytes) or {
				if file.eof() {
					break
				} else {
					eprintln("Failed to read log file. Err: ${err}")
					return
				}
			}
			pos = u64(file.tell() or {
				0
			})
			ch := rune(bytes[0])
			if ch == `\n` {
				lines << builder.str()
				builder.clear()
			}
			builder.write_rune(ch)
		}

		if lines.len > 0 {
			line := lines[lines.len - 1]
			mut joined := regex.regex_opt("([\\w_\\d]+) se ha unido") or { panic(err) }
			joined_start, joined_end := joined.find(line)
			if joined_start != -1 && joined_end != -1 {
				group := joined.get_group_list()[0]
				group_start, group_end := group.start, group.end

				state.username_queue << line[group_start..group_end]
			} else {
				mut online := regex.regex_opt("ONLINE: ([\\w_\\d ,?]+)") or { panic(err) }
				online_start, online_end := online.find(line)
				if online_start != -1 && online_end != -1 {
					group := online.get_group_list()[0]
					group_start, group_end := group.start, group.end

					state.username_queue << line[group_start..group_end].split(", ")
				}
			}
		}

		for state.username_queue.len > 0 {
			username := state.username_queue.first()
			state.username_queue.delete(0)

			spawn print_data(username, apikey)
		}
	}

	file.close()
}

fn cli(mut state &State) {
	os.input("Press enter to quit. ")
	println("quitting...")
	state.is_running = false
}

struct MojangProfile {
	id string
	name string
}

fn get_uuid_from_username(username string) ?string {
	resp := http.get("https://api.mojang.com/users/profiles/minecraft/${username}") or {
		eprintln("Failed to mojang profile request. Error: ${err}")
		return none
	}
	decoded := json.decode(MojangProfile, resp.body) or {
		eprintln("Failed to decode mojang profile request. Error: ${err}")
		return none
	}
	return decoded.id
}

struct HypixelDataPlayerStatsBedwars {
	final_kills_bedwars f32
	final_deaths_bedwars f32
}

struct HypixelDataPlayerStats {
	bedwars HypixelDataPlayerStatsBedwars @[json: Bedwars]
}

struct HypixelDataPlayerAchievements {
	bedwars_level int
}

struct HypixelDataPlayer {
	stats HypixelDataPlayerStats
	achievements HypixelDataPlayerAchievements
}

struct HypixelData {
	player HypixelDataPlayer
}

fn get_hypixel_data(uuid string, apikey string) ?HypixelData {
	mut header := http.Header{};
	header.add_custom("API-Key", apikey) or {
		eprintln("Failed to add custom header. Error: ${err}")
		return none
	}
	config := http.FetchConfig{
		url: "https://api.hypixel.net/v2/player"
		header: header
		params: {
			"uuid": uuid
		}
	}
	resp := http.fetch(config) or {
		eprintln("Failed to send hypixel data request. Error: ${err}")
		return none
	}

	data := json.decode(HypixelData, resp.body) or {
		eprintln("Failed to decode hypixel data request json. Error: ${err}")
		return none
	}

	return data
}