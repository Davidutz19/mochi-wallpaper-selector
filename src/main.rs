//! A Mochi plugin: pick a wallpaper on the island.
//!
//! `toggle` opens the picker (qml/Picker.qml), which reads the wallpapers from
//! the state this publishes and runs `set`. The wallpaper set last is saved, and
//! set again when Mochi starts, retrying while the daemon starts too.

mod daemon;
mod library;

use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use mochi_sdk::{ActivityId, ActivitySpec, ModuleCommand, ModuleCtx, ModuleEvent, Priority, json};
use serde::Deserialize;
use tokio::time::{Instant, sleep_until};

use crate::daemon::Daemon;

#[derive(Debug, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct Settings {
    directory: String,
    recursive: bool,
    daemon: String,
    command: String,
    transition: String,
    restore: bool,
    default: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            directory: "~/Pictures/Wallpapers".into(),
            recursive: false,
            daemon: "auto".into(),
            command: String::new(),
            transition: String::new(),
            restore: true,
            default: String::new(),
        }
    }
}

/// How long the start keeps trying to restore the wallpaper while the daemon
/// comes up, and how often.
const RESTORE_TRIES: u32 = 20;
const RESTORE_EVERY: Duration = Duration::from_millis(500);

struct Selector {
    settings: Settings,
    directory: PathBuf,
    /// `None` is `auto`: detected each time a wallpaper is set.
    daemon: Option<Daemon>,
    wallpapers: Vec<PathBuf>,
    current: Option<PathBuf>,
    /// Why the last attempt failed, for the picker to show.
    error: Option<String>,
    picker: Option<ActivityId>,
    /// The wallpaper to restore and the attempts left, while it fails.
    restoring: Option<(PathBuf, u32)>,
}

fn main() -> std::process::ExitCode {
    mochi_sdk::run(run)
}

async fn run(mut ctx: ModuleCtx) -> Result<(), mochi_sdk::Error> {
    let settings: Settings = ctx.settings()?;
    let directory = library::expand(&settings.directory);
    // A wrong `daemon` stops the plugin with the reason in mochid's log.
    let daemon = Daemon::from_setting(&settings.daemon, &settings.command)?;
    let mut selector = Selector {
        current: saved(),
        directory,
        daemon,
        settings,
        wallpapers: Vec::new(),
        error: None,
        picker: None,
        restoring: None,
    };
    selector.rescan();
    selector.restoring = selector
        .startup_wallpaper()
        .map(|path| (path, RESTORE_TRIES));
    selector.publish(&ctx);

    let mut retry_at = Instant::now();
    loop {
        tokio::select! {
            event = ctx.next_event() => match event {
                None => return Ok(()),
                Some(ModuleEvent::Command(command)) => selector.command(&ctx, command).await,
                Some(ModuleEvent::Ended { activity, .. }) if selector.picker == Some(activity) => {
                    selector.picker = None;
                }
                Some(_) => {}
            },
            () = sleep_until(retry_at), if selector.restoring.is_some() => {
                selector.try_restore(&ctx).await;
                retry_at = Instant::now() + RESTORE_EVERY;
            }
        }
    }
}

impl Selector {
    async fn command(&mut self, ctx: &ModuleCtx, command: ModuleCommand) {
        let action = command.action.clone();
        match action.as_str() {
            "toggle" if self.picker.is_some() => {
                self.close(ctx);
                command.reply(Ok(()));
            }
            "toggle" | "open" => {
                self.open(ctx);
                command.reply(Ok(()));
            }
            "close" => {
                self.close(ctx);
                command.reply(Ok(()));
            }
            "set" => {
                let name = command.args.str("path").unwrap_or_default().to_owned();
                let path = library::resolve(&name, &self.directory);
                let result = self.set(ctx, path).await;
                command.reply(result);
            }
            "next" | "previous" | "random" => {
                self.rescan();
                let result = match self.step(&action) {
                    Some(path) => self.set(ctx, path).await,
                    None => Err(format!("no wallpapers in {}", self.directory.display())),
                };
                command.reply(result);
            }
            "restore" => {
                let result = match self.startup_wallpaper() {
                    Some(path) => self.set(ctx, path).await,
                    None => Err("no wallpaper was set yet, and no default".into()),
                };
                command.reply(result);
            }
            "current" => command.answer(
                self.current
                    .as_ref()
                    .map(|path| path.display().to_string())
                    .ok_or_else(|| "no wallpaper was set yet".to_owned()),
            ),
            "list" => {
                self.rescan();
                let lines: Vec<String> = self
                    .wallpapers
                    .iter()
                    .map(|path| path.display().to_string())
                    .collect();
                command.answer(Ok(lines.join("\n")));
            }
            other => command.reply(Err(format!("wallpaper-selector has no action {other}"))),
        }
    }

    fn open(&mut self, ctx: &ModuleCtx) {
        self.rescan();
        // An error from before is old news once the picker opens again.
        self.error = None;
        self.publish(ctx);
        let mut spec = ActivitySpec::new("Picker")
            .key("picker")
            .priority(Priority::URGENT)
            .uninterruptible()
            .modal();
        // On the monitor you're on, which takes the keyboard.
        if let Some(output) = ctx.compositor().focused_output {
            spec = spec.output(output);
        }
        self.picker = Some(ctx.present(spec));
    }

    fn close(&mut self, ctx: &ModuleCtx) {
        if let Some(id) = self.picker.take() {
            ctx.withdraw(id);
        }
    }

    fn rescan(&mut self) {
        self.wallpapers = library::scan(&self.directory, self.settings.recursive);
    }

    /// The one to set when Mochi starts: the saved one if it still exists,
    /// otherwise the default.
    fn startup_wallpaper(&self) -> Option<PathBuf> {
        let saved = self.current.clone().filter(|path| path.is_file());
        let default = Some(self.settings.default.as_str())
            .filter(|name| !name.is_empty())
            .map(|name| library::resolve(name, &self.directory));
        if self.settings.restore {
            saved.or(default)
        } else {
            default
        }
    }

    /// The next, previous or a random wallpaper after the current one.
    fn step(&self, action: &str) -> Option<PathBuf> {
        let count = self.wallpapers.len();
        if count == 0 {
            return None;
        }
        let at = self
            .current
            .as_ref()
            .and_then(|current| self.wallpapers.iter().position(|path| path == current));
        let index = match (action, at) {
            ("next", Some(at)) => (at + 1) % count,
            ("previous", Some(at)) => (at + count - 1) % count,
            ("previous", None) => count - 1,
            ("random", at) => random_other(count, at),
            _ => 0,
        };
        Some(self.wallpapers[index].clone())
    }

    async fn set(&mut self, ctx: &ModuleCtx, path: PathBuf) -> Result<(), String> {
        let result = self.apply(&path).await;
        match &result {
            Ok(()) => {
                save(&path);
                self.current = Some(path);
                self.error = None;
                self.restoring = None;
            }
            Err(error) => self.error = Some(error.clone()),
        }
        self.publish(ctx);
        result
    }

    async fn apply(&self, path: &Path) -> Result<(), String> {
        if !path.is_file() {
            return Err(format!("no image at {}", path.display()));
        }
        let daemon = match &self.daemon {
            Some(daemon) => daemon.clone(),
            None => Daemon::detect().ok_or(
                "no wallpaper daemon runs: start awww, swww, hyprpaper or swaybg, or set daemon = \"command\"",
            )?,
        };
        daemon.set(path, &self.settings.transition).await
    }

    /// One attempt at the startup wallpaper; gives up quietly after the last.
    async fn try_restore(&mut self, ctx: &ModuleCtx) {
        let Some((path, tries)) = self.restoring.take() else {
            return;
        };
        if self.set(ctx, path.clone()).await.is_err() && tries > 1 {
            self.restoring = Some((path, tries - 1));
        }
    }

    fn publish(&self, ctx: &ModuleCtx) {
        let wallpapers: Vec<_> = self
            .wallpapers
            .iter()
            .map(|path| {
                json!({
                    "path": path.display().to_string(),
                    "name": path.file_stem().unwrap_or_default().to_string_lossy(),
                })
            })
            .collect();
        let daemon = self.daemon.clone().or_else(Daemon::detect);
        ctx.publish_state(json!({
            "directory": self.directory.display().to_string(),
            "wallpapers": wallpapers,
            "current": self.current.as_ref().map(|path| path.display().to_string()),
            "daemon": daemon.as_ref().map(Daemon::name),
            "error": self.error,
        }));
    }
}

/// A wallpaper index other than `current`, from the clock: good enough to
/// shuffle wallpapers.
fn random_other(count: usize, current: Option<usize>) -> usize {
    let nanos = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .map(|elapsed| elapsed.subsec_nanos() as usize)
        .unwrap_or(0);
    match current {
        Some(at) if count > 1 => (at + 1 + nanos % (count - 1)) % count,
        _ => nanos % count,
    }
}

/// Where the wallpaper set last is saved: `$XDG_STATE_HOME/mochi-wallpaper-selector`.
fn state_file() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/state"))
        })?;
    Some(base.join("mochi-wallpaper-selector").join("current"))
}

fn saved() -> Option<PathBuf> {
    let text = std::fs::read_to_string(state_file()?).ok()?;
    let line = text.lines().next()?.trim();
    (!line.is_empty()).then(|| PathBuf::from(line))
}

fn save(path: &Path) {
    let Some(file) = state_file() else {
        return;
    };
    let written = file
        .parent()
        .map_or(Ok(()), std::fs::create_dir_all)
        .and_then(|()| std::fs::write(&file, format!("{}\n", path.display())));
    if let Err(error) = written {
        eprintln!(
            "wallpaper-selector: can't save the wallpaper to {}: {error}",
            file.display()
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn random_never_repeats_the_current_one() {
        for count in 2..10 {
            for at in 0..count {
                let index = random_other(count, Some(at));
                assert!(index < count && index != at);
            }
        }
        assert_eq!(random_other(1, Some(0)), 0);
    }
}
