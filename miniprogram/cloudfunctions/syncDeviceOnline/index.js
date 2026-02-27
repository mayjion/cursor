/**
 * 刷新当前用户设备在线状态
 * 只刷新超过60秒未同步的设备
 */
async function syncDeviceOnline(devices) {

  if (!devices || devices.length === 0) return

  const now = Date.now()
  const needSyncDevices = devices.filter(dev =>
    !dev.lastSyncTime || (now - dev.lastSyncTime > 60000)
  )

  if (needSyncDevices.length === 0) return

  // 按 productId 分组（避免重复生成token）
  const productGroups = {}

  needSyncDevices.forEach(dev => {
    if (!productGroups[dev.productId]) {
      productGroups[dev.productId] = []
    }
    productGroups[dev.productId].push(dev)
  })

  for (const productId in productGroups) {

    // 查密钥
    const resSecret = await db.collection('product_secrets')
      .where({ productId, enable: true })
      .limit(1)
      .get()

    if (resSecret.data.length === 0) continue

    const token = generateToken({
      accessKey: resSecret.data[0].accessKey,
      productId
    })

    for (const dev of productGroups[productId]) {

      try {

        const res = await axios.get(
          'https://iot-api.heclouds.com/device/detail',
          {
            params: {
              product_id: productId,
              device_name: dev.deviceName
            },
            headers: {
              Authorization: token
            },
            timeout: 5000
          }
        )

        const online = res.data?.data?.status === 1

        await db.collection('devices')
          .doc(dev._id)
          .update({
            data: {
              online,
              lastSyncTime: now
            }
          })

      } catch (err) {
        console.error('刷新在线状态失败:', dev.deviceName)
      }
    }
  }
}
