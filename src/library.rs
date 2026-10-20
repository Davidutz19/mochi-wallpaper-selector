//! The wallpapers: the images in the configured directory.

use std::fs;
use std::path::{Path, PathBuf};

/// The image formats the daemons read. swaybg and hyprpaper take fewer; a file
/// they can't read fails when it is set, with the daemon's message.
const EXTENSIONS: [&str; 7] = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "avif"];

/// `~` and `~/...` become the home directory.
pub fn expand(path: &str) -> PathBuf {
    let home = std::env::var_os("HOME").map(PathBuf::from);
    match (path.strip_prefix('~'), home) {
        (Some(""), Some(home)) => home,
        (Some(rest), Some(home)) if rest.starts_with('/') => home.join(&rest[1..]),
        _ => PathBuf::from(path),
    }
}

/// A wallpaper named in a command or a setting: an absolute path, `~/...`, or a
/// path inside the directory.
pub fn resolve(name: &str, directory: &Path) -> PathBuf {
    if name.starts_with('/') || name.starts_with('~') {
        expand(name)
    } else {
        directory.join(name)
    }
}

pub fn is_image(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| EXTENSIONS.contains(&extension.to_ascii_lowercase().as_str()))
}

/// The images in `directory`, by file name. Symbolic links count as what they
/// point to, so a folder of links (home-manager's) works. A missing directory
/// is an empty list.
pub fn scan(directory: &Path, recursive: bool) -> Vec<PathBuf> {
    let mut found = Vec::new();
    collect(directory, recursive, &mut found);
    found.sort_by_cached_key(|path| {
        let name = path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_lowercase();
        (name, path.clone())
    });
    found
}

fn collect(directory: &Path, recursive: bool, found: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(directory) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        // fs::metadata follows links.
        let Ok(metadata) = fs::metadata(&path) else {
            continue;
        };
        if metadata.is_dir() {
            if recursive {
                collect(&path, recursive, found);
            }
        } else if metadata.is_file() && is_image(&path) {
            found.push(path);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "mochi-wallpaper-test-{name}-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn names(paths: Vec<PathBuf>) -> Vec<String> {
        paths
            .iter()
            .map(|path| path.file_name().unwrap().to_string_lossy().into_owned())
            .collect()
    }

    #[test]
    fn scan_keeps_images_sorted_by_name() {
        let dir = temp_dir("scan");
        for name in ["b.PNG", "a.jpg", "notes.txt", "C.webp"] {
            fs::write(dir.join(name), b"x").unwrap();
        }
        fs::create_dir(dir.join("sub")).unwrap();
        fs::write(dir.join("sub/d.jpg"), b"x").unwrap();

        assert_eq!(names(scan(&dir, false)), ["a.jpg", "b.PNG", "C.webp"]);
        assert_eq!(
            names(scan(&dir, true)),
            ["a.jpg", "b.PNG", "C.webp", "d.jpg"]
        );
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn scan_follows_links() {
        let dir = temp_dir("links");
        fs::write(dir.join("real.png"), b"x").unwrap();
        fs::create_dir(dir.join("shown")).unwrap();
        std::os::unix::fs::symlink(dir.join("real.png"), dir.join("shown/link.png")).unwrap();
        assert_eq!(
            scan(&dir.join("shown"), false),
            [dir.join("shown/link.png")]
        );
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn missing_directory_is_empty() {
        assert!(scan(Path::new("/nonexistent/mochi-wallpaper"), true).is_empty());
    }

    #[test]
    fn resolve_names_and_paths() {
        let dir = Path::new("/walls");
        assert_eq!(resolve("sea.jpg", dir), PathBuf::from("/walls/sea.jpg"));
        assert_eq!(resolve("/tmp/x.png", dir), PathBuf::from("/tmp/x.png"));
        assert_eq!(resolve("sub/x.png", dir), PathBuf::from("/walls/sub/x.png"));
    }
}
