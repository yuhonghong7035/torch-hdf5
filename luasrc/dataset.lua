local HDF5DataSet = torch.class("hdf5.HDF5DataSet")

--[[ Get the sizes and max sizes of an HDF5 dataspace, returning them in Lua tables ]]
local function getDataspaceSize(nDims, spaceID)
    local size_t = hdf5.ffi.typeof("hsize_t[" .. nDims .. "]")
    local dims = size_t()
    local maxDims = size_t()
    if hdf5.C.H5Sget_simple_extent_dims(spaceID, dims, maxDims) ~= nDims then
        error("Failed getting dataspace size")
    end
    local size = {}
    local maxSize = {}
    for k = 1, nDims do
        size[k] = tonumber(dims[k-1])
        maxSize[k] = tonumber(maxDims[k-1])
    end
    return size, maxSize
end

function HDF5DataSet:__init(parent, datasetID, dataspaceID)
    assert(parent)
    assert(datasetID)
    assert(dataspaceID)
    self._parent = parent
    self._datasetID = datasetID

    -- TODO separate
    self._dataspaceID = dataspaceID
end

function HDF5DataSet:__tostring()
    return "[HDF5DataSet]" --  TODO  .. self:filename() ..
end

function HDF5DataSet:all()

    local typeID = hdf5.C.H5Dget_type(self._datasetID)
    local nativeType = hdf5.C.H5Tget_native_type(typeID, hdf5.C.H5T_DIR_ASCEND)
    local torchType = hdf5._getTorchType(typeID)
    if not torchType then
        error("Could not find torch type for native type " .. tostring(nativeType))
    end
    if not nativeType then
        error("Cannot find hdf5 native type for " .. torchType)
    end
    local spaceID = hdf5.C.H5Dget_space(self._datasetID)
    if not hdf5.C.H5Sis_simple(spaceID) then
        error("Error: complex dataspaces are not supported!")
    end

    -- Create a new tensor of the correct type and size
    local nDims = hdf5.C.H5Sget_simple_extent_ndims(spaceID)
    local size = getDataspaceSize(nDims, spaceID)
    local factory = torch.factory(torchType)
    if not factory then
        error("No torch factory for type " .. torchType)
    end

    local tensor = factory():resize(unpack(size))

    -- Read data into the tensor
    local dataPtr = torch.data(tensor)
    hdf5.C.H5Dread(self._datasetID, nativeType, hdf5.H5S_ALL, hdf5.H5S_ALL, hdf5.H5P_DEFAULT, dataPtr)
    return tensor

end

function HDF5DataSet:close()
    local status = hdf5.C.H5Dclose(self._datasetID)
    if status < 0 then
        error("Failed closing dataset for " .. tostring(self))
    end
    status = hdf5.C.H5Sclose(self._dataspaceID)
    if status < 0 then
        error("Failed closing dataspace for " .. tostring(self))
    end
end