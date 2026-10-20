//! What sets the wallpaper: a wallpaper daemon, or a command of the user's.

use std::fs;
use std::path::Path;
use std::process::Stdio;

use tokio::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Daemon {
    Awww,
    Swww,
    Hyprpaper,
    Swaybg,
    /// A shell command; `{path}` is the image, quoted.
    Command(String),
}

/// The daemons `auto` looks for, in order, by process name.
const DETECTED: [(&str, Daemon); 4] = [
    ("awww-daemon", Daemon::Awww),
    ("swww-daemon", Daemon::Swww),
    ("hyprpaper", Daemon::Hyprpaper),
    ("swaybg", Daemon::Swaybg),
];

impl Daemon {
    /// The `daemon` setting: `None` for `auto`.
    pub fn from_setting(name: &str, command: &str) -> Result<Option<Self>, String> {
        Ok(Some(match name {
            "auto" => return Ok(None),
            "awww" => Self::Awww,
            "swww" => Self::Swww,
            "hyprpaper" => Self::Hyprpaper,
            "swaybg" => Self::Swaybg,
            "command" if command.trim().is_empty() => {
                return Err("daemon = \"command\" needs a command".into());
            }
            "command" => Self::Command(command.to_owned()),
            other => return Err(format!("unknown daemon {other:?}")),
        }))
    }

    /// The first known daemon that runs.
    pub fn detect() -> Option<Self> {
        let running = running_programs();
        DETECTED
            .into_iter()
            .find(|(process, _)| running.iter().any(|name| name == process))
            .map(|(_, daemon)| daemon)
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::Awww => "awww",
            Self::Swww => "swww",
            Self::Hyprpaper => "hyprpaper",
            Self::Swaybg => "swaybg",
            Self::Command(_) => "command",
        }
    }

    /// The programs that set `path`, run one after the other. swaybg is
    /// different: it is started, see [`Daemon::set`].
    pub fn invocations(&self, path: &Path, transition: &str) -> Vec<Vec<String>> {
        let path = path.to_string_lossy().into_owned();
        let with_transition = |program: &str| {
            let mut args = vec![program.to_owned(), "img".to_owned(), path.clone()];
            if !transition.is_empty() {
                args.extend(["--transition-type".to_owned(), transition.to_owned()]);
            }
            args
        };
        match self {
            Self::Awww => vec![with_transition("awww")],
            Self::Swww => vec![with_transition("swww")],
            // `preload` is gone from newer hyprpaper and fails there; `wallpaper`
            // with an empty monitor covers every monitor.
            Self::Hyprpaper => vec![
                vec![
                    "hyprctl".into(),
                    "hyprpaper".into(),
                    "preload".into(),
                    path.clone(),
                ],
                vec![
                    "hyprctl".into(),
                    "hyprpaper".into(),
                    "wallpaper".into(),
                    format!(",{path}"),
                ],
            ],
            Self::Swaybg => vec![vec![
                "swaybg".into(),
                "-m".into(),
                "fill".into(),
                "-i".into(),
                path,
            ]],
            Self::Command(command) => {
                vec![vec![
                    "sh".into(),
                    "-c".into(),
                    command.replace("{path}", &shell_quote(&path)),
                ]]
            }
        }
    }

    pub async fn set(&self, path: &Path, transition: &str) -> Result<(), String> {
        let invocations = self.invocations(path, transition);
        if *self == Self::Swaybg {
            return start_swaybg(&invocations[0]).await;
        }
        let last = invocations.len() - 1;
        for (index, args) in invocations.iter().enumerate() {
            let result = run(args).await;
            // hyprpaper's preload only matters on versions that have it.
            if index < last && *self == Self::Hyprpaper {
                continue;
            }
            result?;
        }
        Ok(())
    }
}

async fn run(args: &[String]) -> Result<(), String> {
    let output = Command::new(&args[0])
        .args(&args[1..])
        .stdin(Stdio::null())
        .output()
        .await
        .map_err(|error| format!("{}: {error}", args[0]))?;
    if output.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&output.stderr);
    let message = stderr.trim();
    Err(if message.is_empty() {
        format!("{} failed ({})", args[0], output.status)
    } else {
        format!("{}: {message}", args[0])
    })
}

/// swaybg shows one image for as long as it runs: start one with the new image,
/// then stop the ones that were there, so the screen is never empty.
async fn start_swaybg(args: &[String]) -> Result<(), String> {
    let old = pids_of("swaybg");
    let mut child = Command::new(&args[0])
        .args(&args[1..])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("swaybg: {error}"))?;
    // A swaybg that can't read the image exits at once.
    tokio::time::sleep(std::time::Duration::from_millis(400)).await;
    if let Ok(Some(status)) = child.try_wait() {
        return Err(format!("swaybg exited ({status})"));
    }
    if !old.is_empty() {
        let _ = Command::new("kill").args(&old).status().await;
    }
    Ok(())
}

/// Quotes a string for `sh`.
pub fn shell_quote(text: &str) -> String {
    format!("'{}'", text.replace('\'', r"'\''"))
}

/// The names of the programs that run, from /proc.
fn running_programs() -> Vec<String> {
    processes().map(|(_, name)| name).collect()
}

fn pids_of(program: &str) -> Vec<String> {
    processes()
        .filter(|(_, name)| name == program)
        .map(|(pid, _)| pid)
        .collect()
}

fn processes() -> impl Iterator<Item = (String, String)> {
    fs::read_dir("/proc")
        .into_iter()
        .flatten()
        .flatten()
        .filter_map(|entry| {
            let pid = entry.file_name().to_string_lossy().into_owned();
            if !pid.bytes().all(|byte| byte.is_ascii_digit()) {
                return None;
            }
            let name = fs::read_to_string(entry.path().join("comm")).ok()?;
            Some((pid, name.trim_end().to_owned()))
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn strings(lists: Vec<Vec<String>>) -> Vec<Vec<&'static str>> {
        lists
            .into_iter()
            .map(|list| {
                list.into_iter()
                    .map(|arg| &*Box::leak(arg.into_boxed_str()))
                    .collect()
            })
            .collect()
    }

    #[test]
    fn settings() {
        assert_eq!(Daemon::from_setting("auto", ""), Ok(None));
        assert_eq!(Daemon::from_setting("swww", ""), Ok(Some(Daemon::Swww)));
        assert!(Daemon::from_setting("command", " ").is_err());
        assert!(Daemon::from_setting("feh", "").is_err());
    }

    #[test]
    fn awww_with_and_without_transition() {
        let path = Path::new("/w/sea.jpg");
        assert_eq!(
            strings(Daemon::Awww.invocations(path, "")),
            [["awww", "img", "/w/sea.jpg"]]
        );
        assert_eq!(
            strings(Daemon::Swww.invocations(path, "grow")),
            [["swww", "img", "/w/sea.jpg", "--transition-type", "grow"]]
        );
    }

    #[test]
    fn hyprpaper_covers_every_monitor() {
        let calls = strings(Daemon::Hyprpaper.invocations(Path::new("/w/a.png"), "fade"));
        assert_eq!(calls[1], ["hyprctl", "hyprpaper", "wallpaper", ",/w/a.png"]);
    }

    #[test]
    fn command_quotes_the_path() {
        let daemon = Daemon::Command("feh --bg-fill {path}".into());
        let calls = strings(daemon.invocations(Path::new("/w/it's here.png"), ""));
        assert_eq!(
            calls,
            [["sh", "-c", r"feh --bg-fill '/w/it'\''s here.png'"]]
        );
    }
}
