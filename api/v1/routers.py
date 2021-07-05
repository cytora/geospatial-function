from fastapi import APIRouter
from . import geospatial_general

router = APIRouter()
router.include_router(geospatial_general.router, tags=['GeoSpatial LatLon Caller General'])
