/// A point in device-independent pixels from a monitor's top left, y counting down.
#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct Point {
    pub x: f32,
    pub y: f32,
}

impl Point {
    pub const fn new(x: f32, y: f32) -> Self {
        Point { x, y }
    }

    pub fn distance(self, other: Point) -> f32 {
        ((other.x - self.x).powi(2) + (other.y - self.y).powi(2)).sqrt()
    }

    /// This point moved onto the nearest of the eight 45 degree directions from `origin`,
    /// projected rather than rotated, so a drag along an axis keeps its exact length.
    pub fn snapped45(self, origin: Point) -> Point {
        let dx = self.x - origin.x;
        let dy = self.y - origin.y;
        let (ax, ay) = (dx.abs(), dy.abs());
        let tan22 = 0.414_213_56;
        if ay <= ax * tan22 {
            return Point::new(origin.x + dx, origin.y);
        }
        if ax <= ay * tan22 {
            return Point::new(origin.x, origin.y + dy);
        }
        let diagonal = (ax + ay) / 2.0;
        Point::new(origin.x + diagonal.copysign(dx), origin.y + diagonal.copysign(dy))
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Default)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

/// A smooth curve through a freehand stroke's points, Catmull-Rom style, as cubic Bezier
/// segments: each is the two control points and the end. The curve starts at the first point.
pub fn smooth(points: &[Point]) -> Vec<(Point, Point, Point)> {
    if points.len() < 2 {
        return Vec::new();
    }
    (0..points.len() - 1)
        .map(|index| {
            let p0 = points[index.saturating_sub(1)];
            let p1 = points[index];
            let p2 = points[index + 1];
            let p3 = points[(index + 2).min(points.len() - 1)];
            (
                Point::new(p1.x + (p2.x - p0.x) / 6.0, p1.y + (p2.y - p0.y) / 6.0),
                Point::new(p2.x - (p3.x - p1.x) / 6.0, p2.y - (p3.y - p1.y) / 6.0),
                p2,
            )
        })
        .collect()
}

/// A straight arrow whose body widens from a thin tail to a swept back head, as Tinysnap draws
/// it: the outline's corners, to be filled and stroked with round joins.
pub fn arrow_outline(tail: Point, tip: Point, width: f32) -> Vec<Point> {
    let length = tail.distance(tip);
    if length <= 0.0 {
        return Vec::new();
    }
    let (ux, uy) = ((tip.x - tail.x) / length, (tip.y - tail.y) / length);
    let (nx, ny) = (-uy, ux);
    let head = (length * 0.5).min(width * 4.2);
    let head_half = head * 0.62;
    let neck_half = (width * 0.6).min(head_half * 0.5);
    let tail_half = width * 0.18;
    let base = Point::new(tip.x - ux * head, tip.y - uy * head);
    // The barbs sit a little behind the neck, which sweeps the head back.
    let barb = Point::new(base.x - ux * head * 0.12, base.y - uy * head * 0.12);
    let at = |point: Point, offset: f32| Point::new(point.x + nx * offset, point.y + ny * offset);
    vec![
        at(tail, tail_half),
        at(base, neck_half),
        at(barb, head_half),
        tip,
        at(barb, -head_half),
        at(base, -neck_half),
        at(tail, -tail_half),
    ]
}

/// The laser pointer's trail: where the pointer has been in the last 0.7 s, each point fading as
/// it ages. Nothing of it is kept.
#[derive(Default)]
pub struct LaserTrail {
    points: Vec<(Point, f64)>,
}

impl LaserTrail {
    pub const FADE: f64 = 0.7;

    pub fn add(&mut self, point: Point, time: f64) {
        self.points.push((point, time));
    }

    /// The points still showing at `now`, oldest first, with how opaque each is.
    pub fn visible(&self, now: f64) -> Vec<(Point, f32)> {
        self.points
            .iter()
            .filter_map(|&(point, time)| {
                let age = now - time;
                (age < Self::FADE).then(|| (point, (1.0 - age.max(0.0) / Self::FADE) as f32))
            })
            .collect()
    }

    pub fn prune(&mut self, now: f64) {
        self.points.retain(|&(_, time)| now - time < Self::FADE);
    }

    /// Nothing left to fade, so the screen need not be redrawn until the pointer moves again.
    pub fn is_idle(&self, now: f64) -> bool {
        self.visible(now).is_empty()
    }
}

/// The zoom lens: a circle on the pointer showing the screen under it magnified.
pub struct Lens;

impl Lens {
    pub const RADIUS: f32 = 120.0;
    pub const MIN: f32 = 1.5;
    pub const MAX: f32 = 6.0;

    /// The magnification after a scroll of `notches`, about 1.15 times per notch.
    pub fn magnification(current: f32, notches: f32) -> f32 {
        (current * 1.15_f32.powf(notches)).clamp(Self::MIN, Self::MAX)
    }

    /// The part of the screen the lens shows, centred on the pointer.
    pub fn source(center: Point, radius: f32, magnification: f32) -> Rect {
        let half = radius / magnification;
        Rect { x: center.x - half, y: center.y - half, width: half * 2.0, height: half * 2.0 }
    }
}

/// The spotlight: every monitor dimmed except a circle round the pointer.
pub struct Spotlight;

impl Spotlight {
    pub const RADIUS: f32 = 140.0;

    /// The radius after growing by `delta` pixels, kept between 60 and 600.
    pub fn radius(current: f32, delta: f32) -> f32 {
        (current + delta).clamp(60.0, 600.0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_smooth_stroke_ends_where_the_pointer_did() {
        let points = [Point::new(0.0, 0.0), Point::new(10.0, 5.0), Point::new(20.0, 0.0), Point::new(30.0, 8.0)];
        let segments = smooth(&points);
        assert_eq!(segments.len(), 3);
        assert_eq!(segments.last().unwrap().2, Point::new(30.0, 8.0));
    }

    #[test]
    fn the_arrow_ends_at_its_tip() {
        let outline = arrow_outline(Point::new(0.0, 0.0), Point::new(100.0, 0.0), 6.0);
        assert_eq!(outline.len(), 7);
        assert_eq!(outline[3], Point::new(100.0, 0.0));
        assert!(arrow_outline(Point::new(5.0, 5.0), Point::new(5.0, 5.0), 6.0).is_empty());
    }

    #[test]
    fn the_trail_fades_over_seven_tenths_of_a_second() {
        let mut trail = LaserTrail::default();
        trail.add(Point::new(0.0, 0.0), 10.0);
        trail.add(Point::new(5.0, 0.0), 10.35);
        let visible = trail.visible(10.35);
        assert_eq!(visible.len(), 2);
        assert!((visible[0].1 - 0.5).abs() < 0.001);
        assert_eq!(visible[1].1, 1.0);
    }

    #[test]
    fn points_older_than_the_fade_are_gone() {
        let mut trail = LaserTrail::default();
        trail.add(Point::new(0.0, 0.0), 10.0);
        trail.add(Point::new(5.0, 0.0), 10.5);
        trail.prune(10.8);
        assert_eq!(trail.visible(10.8).iter().map(|v| v.0).collect::<Vec<_>>(), vec![Point::new(5.0, 0.0)]);
        assert!(!trail.is_idle(10.8));
        assert!(trail.is_idle(11.3));
    }

    #[test]
    fn zoom_stays_between_one_and_a_half_and_six() {
        assert_eq!(Lens::magnification(2.0, 100.0), 6.0);
        assert_eq!(Lens::magnification(2.0, -100.0), 1.5);
        assert!(Lens::magnification(2.0, 1.0) > 2.0);
    }

    #[test]
    fn the_lens_shows_the_square_round_the_pointer() {
        let source = Lens::source(Point::new(500.0, 300.0), 120.0, 2.0);
        assert_eq!(source, Rect { x: 440.0, y: 240.0, width: 120.0, height: 120.0 });
    }

    #[test]
    fn the_spotlight_stays_between_60_and_600() {
        assert_eq!(Spotlight::radius(140.0, 1000.0), 600.0);
        assert_eq!(Spotlight::radius(140.0, -1000.0), 60.0);
        assert_eq!(Spotlight::radius(140.0, 10.0), 150.0);
    }

    #[test]
    fn shift_keeps_an_arrow_to_45_degrees() {
        let origin = Point::new(100.0, 100.0);
        assert_eq!(Point::new(200.0, 110.0).snapped45(origin), Point::new(200.0, 100.0));
        assert_eq!(Point::new(190.0, 210.0).snapped45(origin), Point::new(200.0, 200.0));
    }
}
