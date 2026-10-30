"""Species-style wrapper around the approved human rig (crew_v2) so the compositor and previews treat it like the others."""
from sp_common import *
import crew_v2 as cv2

class Human(Species):
    id = 'human'
    walk_fps = 8
    head_names = ['hair', 'helmet']
    def legs(self): return cv2.legs()
    def torso(self): return cv2.torso()
    def arms(self, pose): return cv2.arms(pose)
    def head(self, name): return cv2.head(name)
    def torso_anchors(self): return {'head': [16, 14], 'back': [16, 24], 'shoulder_l': [8, 14], 'shoulder_r': [24, 14]}
    def arm_anchors(self): return {p: {k: (list(v) if v else None) for k, v in cv2.ARM[p].items()} for p in cv2.POSES}
