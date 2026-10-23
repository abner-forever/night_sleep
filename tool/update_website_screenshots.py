import argparse
from pathlib import Path

from PIL import Image


SCREENS = {
    'home': 'home',
    'session': 'session-setup',
    'stats': 'statistics',
    'all-data': 'history',
    'detail': 'detail',
    'settings': 'settings',
    'sounds': 'session-sounds',
}
TABLET_SCREENS = {'home', 'session', 'stats', 'settings', 'sounds'}
README_IMAGES = {
    'home', 'session', 'stats', 'all-data', 'detail', 'settings', 'sounds',
    'home-dark', 'ipad-home', 'ipad-stats', 'ipad-stats-dark',
}


def main():
    parser = argparse.ArgumentParser(
        description='从界面巡检截图更新官网与 README 图片',
    )
    parser.add_argument(
        'capture_directory', type=Path, help='包含 iphone / ipad 目录的截图路径',
    )
    arguments = parser.parse_args()
    repository = Path(__file__).resolve().parent.parent
    sources = []
    for device in ('iphone', 'ipad'):
        prefix = 'ipad-' if device == 'ipad' else ''
        for screen, checkpoint in SCREENS.items():
            if device == 'ipad' and screen not in TABLET_SCREENS:
                continue
            for theme in ('light', 'dark'):
                source = (
                    arguments.capture_directory / device / f'{checkpoint}-{theme}.png'
                )
                suffix = '-dark' if theme == 'dark' else ''
                name = f'{prefix}{screen}{suffix}'
                sources.append((source, name, 1000 if device == 'ipad' else 720))
    missing = [str(source) for source, _, _ in sources if not source.is_file()]
    if missing:
        parser.error('缺少截图：\n' + '\n'.join(missing))
    for source, name, width in sources:
        with Image.open(source) as original:
            image = original.convert('RGB')
            height = round(image.height * width / image.width)
            image = image.resize((width, height), Image.Resampling.LANCZOS)
            image.save(
                repository / 'website/public/screenshots' / f'{name}.webp',
                quality=86, method=6,
            )
            if name in README_IMAGES:
                image.save(repository / 'docs/images' / f'{name}.png', optimize=True)
            print(f'{name}: {image.width} × {image.height}')


if __name__ == '__main__':
    main()
