package com.ignacioli.finecoach.storage.dao

import androidx.room.Dao
import androidx.room.Query
import androidx.room.Update
import com.ignacioli.finecoach.storage.entity.CoursePackageEntity
import com.ignacioli.finecoach.storage.entity.CreditAdjustmentEntity
import java.util.UUID

@Dao
interface T007PackageDao {
    @Update
    fun updateCoursePackage(row: CoursePackageEntity): Int

    @Query("DELETE FROM active_package_claims WHERE studentID = :studentID")
    fun deleteActivePackageClaim(studentID: UUID): Int

    @Query("SELECT * FROM course_packages WHERE studentID = :studentID")
    fun listCoursePackages(studentID: UUID): List<CoursePackageEntity>

    @Query("SELECT * FROM credit_adjustments WHERE packageID = :packageID")
    fun listCreditAdjustments(packageID: UUID): List<CreditAdjustmentEntity>

    @Query("SELECT * FROM credit_adjustments WHERE sourceEventKey = :sourceEventKey LIMIT 1")
    fun findCreditAdjustmentBySourceEventKey(sourceEventKey: String): CreditAdjustmentEntity?

    @Query(
        """
        SELECT ca.* FROM credit_adjustments AS ca
        INNER JOIN course_packages AS cp ON cp.id = ca.packageID
        WHERE cp.studentID = :studentID
        """,
    )
    fun listStudentCreditAdjustments(studentID: UUID): List<CreditAdjustmentEntity>
}
