#!/usr/bin/env python3
"""
App Icon Generator - Green Motion
Creates app icons with green background and white 'G' letter
"""

from PIL import Image, ImageDraw, ImageFont
import os

def create_app_icon(size, output_path):
    """Create a single app icon with given size"""
    # Create image with green background
    img = Image.new('RGB', (size, size), color=(51, 178, 76))  # Green color
    draw = ImageDraw.Draw(img)
    
    # Calculate font size (70% of image size)
    font_size = int(size * 0.7)
    
    try:
        # Try to use a system font (bold)
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
    except:
        # Fallback to default font
        font = ImageFont.load_default()
    
    # Draw white 'G' letter in the center
    text = "G"
    
    # Get text bounding box
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    
    # Calculate position to center the text
    x = (size - text_width) / 2 - bbox[0]
    y = (size - text_height) / 2 - bbox[1]
    
    # Draw the text
    draw.text((x, y), text, fill=(255, 255, 255), font=font)
    
    # Add subtle shadow effect
    shadow_offset = max(2, int(size * 0.01))
    draw.text((x + shadow_offset, y + shadow_offset), text, fill=(0, 0, 0, 50), font=font)
    draw.text((x, y), text, fill=(255, 255, 255), font=font)
    
    # Save the image
    img.save(output_path, 'PNG')
    print(f"✅ Created: {output_path} ({size}x{size})")

def main():
    # Icon sizes for iOS (all required sizes)
    sizes = {
        'Icon-20.png': 20,
        'Icon-20@2x.png': 40,
        'Icon-20@3x.png': 60,
        'Icon-29.png': 29,
        'Icon-29@2x.png': 58,
        'Icon-29@3x.png': 87,
        'Icon-40.png': 40,
        'Icon-40@2x.png': 80,
        'Icon-40@3x.png': 120,
        'Icon-60@2x.png': 120,
        'Icon-60@3x.png': 180,
        'Icon-76.png': 76,
        'Icon-76@2x.png': 152,
        'Icon-83.5@2x.png': 167,
        'Icon-1024.png': 1024,  # App Store
    }
    
    # Create icons directory
    icons_dir = 'AppIcons'
    os.makedirs(icons_dir, exist_ok=True)
    
    print("🎨 Creating app icons...")
    print("=" * 50)
    
    # Generate all icon sizes
    for filename, size in sizes.items():
        output_path = os.path.join(icons_dir, filename)
        create_app_icon(size, output_path)
    
    print("=" * 50)
    print(f"✅ All icons created in '{icons_dir}' directory")
    print("\n📝 Next steps:")
    print("1. Open Xcode")
    print("2. Go to Assets.xcassets")
    print("3. Select AppIcon")
    print("4. Drag and drop the icons from 'AppIcons' folder")
    print("   to the corresponding slots")

if __name__ == '__main__':
    main()

